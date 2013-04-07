_ = require('underscore')
credentials = require('./credentials')
twilio = require('twilio')(credentials.twilio.account_sid, credentials.twilio.auth_token)
MsTranslator = require('mstranslator');
translator = new MsTranslator
  client_id: credentials.mstranslate.client_id, 
  client_secret: credentials.mstranslate.client_secret;

server = require('nano')('https://autotrans.iriscouch.com')
db = server.use('messages')

processed_texts = {}

db.list((err, body) ->
  body.rows.forEach((doc) ->
    processed_texts[doc.id] = true
  )
  processTexts()
)

processTexts = -> 
  twilio.listSms(to: credentials.twilio.number, (err, data) ->
    messages = _.groupBy(data.smsMessages, 'sid')
    unprocessed = _.filter(_.keys(messages), (k) -> !processed_texts[k])
    if unprocessed.length == 0
      setTimeout(processTexts, 100)
      return

    _.each(unprocessed, (key) -> 
      msg = messages[key][0]
      
      processed_texts[msg.sid] = true
      db.insert({}, msg.sid)

      number_regex = /@1?(\d{10})/
      to_lang_regex = /#(\w{2,3}(?:-CHT|-CHS)?)/

      to_number_match = msg.body.match(number_regex)
      from_number_match = msg.from.match(number_regex)
      if not to_number_match
        setTimeout(processTexts, 100)
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
            console.log("Sending #{data} to: #{to_number}")
            twilio.sendSms({from: credentials.twilio.number, to: "+1#{to_number}", body: data}, (err, data) ->
              if err
                console.log("Error sending SMS: #{_.pairs(err)}.")
              setTimeout(processTexts, 100)
            )
          )
        )
      )
    )
  )
