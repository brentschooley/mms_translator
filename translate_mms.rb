require 'sinatra'
require 'twilio-ruby'
require 'unirest'
require 'sinatra/run-later'
require 'bing_translator'

mashape_key = ENV['MASHAPE_KEY']
bing_translate_id = ENV['BING_TRANSLATE_ID']
bing_translate_secret = ENV['BING_TRANSLATE_SECRET']
twilio_accountsid = ENV['TWILIO_ACCOUNT_SID']
twilio_authtoken = ENV['TWILIO_AUTH_TOKEN']

def check_language(language)
  case language
  when /spanish/
    return "es"
  when /french/
    return "fr"
  when /german/
    return "de"
  when /italian/
    return "it"
  when /klingon/
    return "tlh"
  else
    return nil
  end
end

before do
  # Set up some variables to use in the run_later code.
  @requested_language = params[:Body].strip
  @picture_url = params[:MediaUrl0]
  @incoming_number = params[:From]
end

post '/translate' do
  # This block will execute after the /translate endpoint returns
  run_later do
    token_response = Unirest.post "https://camfind.p.mashape.com/image_requests",
    headers:{
      "X-Mashape-Key" => mashape_key
      },
      parameters:{
       "image_request[locale]" => "en_US",
       "image_request[remote_image_url]" => @picture_url
     }

     token = token_response.body['token']

  # Need to wait for image analysis
  sleep(60)

  # Get the details from the analysis
  image_response = Unirest.get "https://camfind.p.mashape.com/image_responses/#{token}",
  headers:{"X-Mashape-Key" => mashape_key}

  status = image_response.body['status']
  description = image_response.body['name']

  translator = BingTranslator.new(bing_translate_id, bing_translate_secret)
  translated = translator.translate description, :from => 'en', :to => @language_format

  client = Twilio::REST::Client.new twilio_accountsid, twilio_authtoken
  client.account.messages.create(
    to: @incoming_number, 
    from: '+12028001180', 
    body: "Got it, I think your picture contains: #{description}. In #{@requested_language} that would be: #{translated}"
    )
  end

  if @requested_language.nil? || @requested_language.empty?
    # Default to French
    @requested_language = "French"
  end

  if @requested_language.downcase == "list"
    # Return the allowed language list...
    twiml = Twilio::TwiML::Response.new do |r|
      r.Message "Supported languages for translation are: Spanish, French, German, Italian, and Klingon. Please send one of these with a picture and I'll translate it for you! Default language is French if one is not specified."
    end

    return twiml.text
  end

  if @picture_url.nil? || @picture_url.empty?
    twiml = Twilio::TwiML::Response.new do |r|
      r.Message "No image sent. Please send a picture with text indicating a supported translation language."
    end

    return twiml.text
  end

  # Check language
  @language_format = check_language(@requested_language.downcase)

  if @language_format.nil?
    twiml = Twilio::TwiML::Response.new do |r|
      r.Message "#{@requested_language} is not a supported translator language. Supported languages for translation are: Spanish, French, German, Italian, and Klingon. Please send one of these along with a picture and I'll translate it for you!"
    end

    return twiml.text
  end

  content_type "text/xml"

  # Provide a quick response before processing the image with Camfind.
  twiml = Twilio::TwiML::Response.new do |r|
    r.Message "Analyzing your image...then I'll translate it. This may take a few..."
  end

  twiml.text
end
