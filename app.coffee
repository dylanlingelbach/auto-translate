_ = require('underscore')
credentials = require('./credentials')
twilio = require('twilio')(credentials.twilio.account_sid, credentials.twilio.auth_token)
MsTranslator = require('mstranslator');
translator = new MsTranslator
  client_id: credentials.mstranslate.client_id, 
  client_secret: credentials.mstranslate.client_secret;

processed_texts = {}

processTexts = -> 
  twilio.listSms(to: credentials.twilio.number, (err, data) ->
    messages = _.groupBy(data.smsMessages, 'sid')
    unprocessed = _.filter(_.keys(messages), (k) -> !processed_texts[k])
    if unprocessed.length == 0
      setTimeout(processTexts, 100)
      return

    _.each(unprocessed, (key) -> 
      msg = messages[key][0]
      params = 
        text: msg.body
        from: 'en'
        to: 'es'
      processed_texts[msg.sid] = true
      translator.initialize_token((keys) ->
        translator.translate(params, (err, data) ->
          twilio.sendSms({from: msg.to, to: msg.from, body: data}, (err, data) ->
            setTimeout(processTexts, 100)
          )
        )
      )
    )
  )

processTexts()