_ = require('underscore')
credentials = require('./credentials')
twilio = require('twilio')(credentials.twilio.account_sid, credentials.twilio.auth_token)
TwimlResponse = require('twilio').TwimlResponse
MsTranslator = require('mstranslator');
translator = new MsTranslator
  client_id: credentials.mstranslate.client_id, 
  client_secret: credentials.mstranslate.client_secret;

restify = require('restify')
bunyan = require('bunyan')
server = require('nano')(credentials.couch.url)
db = server.use('messages')

processed_texts = {}

handleUnprocessedTexts = (callback) ->
  callback = callback || ->
  twilio.listSms(to: credentials.twilio.number, (err, data) ->
    messages = _.groupBy(data.smsMessages, 'sid')
    unprocessed = _.filter(_.keys(messages), (k) -> !processed_texts[k])
    _.each(unprocessed, (key) -> 
      msg = messages[key][0]
      receiveText(msg)
    )

    return callback()
  )

receiveText = (msg) ->
  processed_texts[msg.sid] = true
  db.insert({}, msg.sid)

  number_regex = /@1?(\d{10})/
  to_lang_regex = /#(\w{2,3}(?:-CHT|-CHS)?)/

  to_number_match = msg.body.match(number_regex)
  if not to_number_match
    error_message = "Unable to find number in #{msg.body}"
    console.log(error_message)
    return

  to_lang_match = msg.body.match(to_lang_regex)

  to_number = to_number_match[1]
  to_lang = 'es'
  if to_lang_match
    to_lang = to_lang_match[1]

  console.log("Translating #{msg.body} to #{to_lang}")

  text = msg.body

  text = text.replace(number_regex, '')
  text = text.replace(to_lang_regex, '')

  translateAndSend(text, to_lang, to_number)

translateAndSend = (text, to_lang, to_number) ->
  translator.initialize_token((keys) ->
    translator.detect({text: text}, (err, lang) ->
      console.log("Detected #{lang}")
      params = 
        text: text
        from: lang
        to: to_lang
      translator.translate(params, (err, data) ->
        if err
          console.log("Error translating: #{err}")
          return

        console.log("Sending #{data} to: #{to_number}")
        twilio.sendSms({from: credentials.twilio.number, to: "+1#{to_number}", body: data}, (err, data) ->
          if err
            console.log("Error sending SMS: #{_.pairs(err)}.")
        )
      )
    )
  )

listenForMessages = ->
  server = restify.createServer({
    name: 'auto-translate',
    version: '1.0.0'
  });
  server.use(restify.acceptParser(server.acceptable))
  server.use(restify.dateParser())
  server.use(restify.queryParser())
  server.use(restify.jsonp())
  server.use(restify.gzipResponse())
  server.use(restify.bodyParser())

  server.post('/sms', (req, res) ->
    msg = 
      body: req.context.Body
      sid: req.context.SmsMessageSid
      from: req.context.From
    receiveText(msg)
    res.send({})
  )

  server.post('/voicemail', (req, res) ->
    twiml = new TwimlResponse()
    twiml
      .say('Thanks for your call.  Please leave a message after the tone and someone will get back to you shortly.')
      .record({transcribeCallback: '/transcription'})
    res.writeHead(200, {'Content-Type': 'text/xml'})
    res.end(twiml.toString());
  )

  server.post('/transcription', (req, res) ->
    text = req.context.TranscriptionText
    console.log("Received transcription: #{text}")
    translateAndSend(text, 'es', credentials.twilio.test_number)
  )

  server.listen(1337, ->
    console.log('Listening on port 1337')
  )

db.list((err, body) ->
  body.rows.forEach((doc) ->
    processed_texts[doc.id] = true
  )
  handleUnprocessedTexts(listenForMessages)
)

