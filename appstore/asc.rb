# frozen_string_literal: true

# App Store listing for Open Teleprompter, applied through the App Store Connect API.
# Safe to run again: every step updates what is there.
#
#   ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_PATH=AuthKey_….p8 ruby appstore/asc.rb metadata   # texts, category, age rating, price, screenshots
#   … ruby appstore/asc.rb submit [build]                                                       # attach the build and send to review
#
# The key is the team's App Store Connect API key (1Password: "App Store Connect - Wave upload").
# Not available in the API, done once by hand in App Store Connect: creating the app and App Privacy
# ("Data Not Collected").
require "base64"
require "digest"
require "json"
require "net/http"
require "openssl"
require "uri"

APP_ID = "6829918822"
LOCALE = "es-MX"
SCREENSHOTS = %w[ready recording editor].map { |name| File.join(__dir__, "#{name}.png") }

INFO = {
  name: "Open Teleprompter",
  subtitle: "Graba leyendo tu texto",
  privacyPolicyUrl: "https://urcalab.com/teleprompter/privacidad/"
}.freeze

VERSION = {
  description: <<~TEXT.strip,
    Open Teleprompter es una cámara de video con tu texto encima. Escribe o pega tu guion, toca grabar y el texto empieza a subir solo, justo bajo la cámara, para que hables mirando al lente. Al terminar, el video queda guardado en Fotos.

    CÓMO FUNCIONA
    1. Escribe o pega tu texto.
    2. Elige el tamaño de la letra y la velocidad.
    3. Graba con el botón rojo o con los botones de volumen.
    4. El video se guarda solo en Fotos.

    Mientras grabas, toca el texto para pausarlo y arrástralo para avanzar o volver atrás.

    IGUAL QUE LA CÁMARA
    • Cámara frontal y trasera, con gran angular y teleobjetivo si tu iPhone los tiene.
    • Toca para enfocar y pellizca para hacer zoom.
    • Linterna, botones de volumen y Control de Cámara para grabar.
    • Video vertical en 1080p, listo para Reels, TikTok o Shorts.

    GRATIS Y PRIVADA
    • Gratis, sin anuncios, sin suscripción y sin cuenta.
    • Sin internet: no envía nada a ningún servidor.
    • No recopila datos. Solo puede agregar videos a Fotos; no ve tu galería.
    • Código abierto: github.com/urcalab/open-teleprompter
  TEXT
  keywords: "prompter,guion,apuntador,grabar,video,cámara,leer,texto,reels,tiktok,shorts,youtube,discurso,selfie",
  marketingUrl: "https://urcalab.com/teleprompter/",
  supportUrl: "https://github.com/urcalab/open-teleprompter/blob/main/SUPPORT.md",
  promotionalText: "Graba mirando al lente: tu guion sube solo mientras hablas. Gratis, sin anuncios y sin recopilar datos."
}.freeze

REVIEW_NOTES = <<~TEXT.strip
  Open Teleprompter is a video camera with a scrolling script on top, for recording yourself while reading.

  How to test:
  1. Allow Camera, Microphone and adding to Photos when asked.
  2. Tap the text box (or the pencil) to edit the script, then tap "Listo".
  3. Tap the red button: recording starts and the script scrolls up. Tap the text to pause it, drag it to move.
  4. Tap the red button again: the video is saved to Photos automatically (the thumbnail at the bottom left opens Photos).

  The app has no account, makes no network requests and collects no data. Photos access is add-only. Source code: https://github.com/urcalab/open-teleprompter
TEXT

module Asc
  module_function

  def jwt
    key = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))
    encode = ->(data) { Base64.urlsafe_encode64(data, padding: false) }
    header = encode.call({alg: "ES256", kid: ENV.fetch("ASC_KEY_ID"), typ: "JWT"}.to_json)
    now = Time.now.to_i
    payload = encode.call({iss: ENV.fetch("ASC_ISSUER_ID"), iat: now, exp: now + 900, aud: "appstoreconnect-v1"}.to_json)
    der = key.sign(OpenSSL::Digest.new("SHA256"), "#{header}.#{payload}")
    r, s = OpenSSL::ASN1.decode(der).value.map { |part| part.value.to_s(2).rjust(32, "\x00".b) }
    "#{header}.#{payload}.#{encode.call(r + s)}"
  end

  def call(method, path, body = nil)
    uri = URI(path.start_with?("http") ? path : "https://api.appstoreconnect.apple.com#{path}")
    request = Net::HTTP.const_get(method.to_s.capitalize).new(uri)
    request["Authorization"] = "Bearer #{jwt}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json if body
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
    [response.code.to_i, response.body.to_s.empty? ? {} : JSON.parse(response.body)]
  end

  def request!(method, path, body = nil)
    status, json = call(method, path, body)
    abort "#{method.upcase} #{path} → #{status}: #{json.to_json}" unless (200..299).cover?(status)
    json
  end

  def get!(path) = request!(:get, path)
end

def version
  Asc.get!("/v1/apps/#{APP_ID}/appStoreVersions?filter[platform]=IOS")["data"]
    .find { |row| %w[PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED].include?(row.dig("attributes", "appStoreState")) } or
    abort "No editable App Store version"
end

def app_info
  Asc.get!("/v1/apps/#{APP_ID}/appInfos")["data"].find { |row| row.dig("attributes", "state") != "READY_FOR_DISTRIBUTION" }
end

def metadata
  Asc.request!(:patch, "/v1/apps/#{APP_ID}", {data: {type: "apps", id: APP_ID, attributes: {contentRightsDeclaration: "DOES_NOT_USE_THIRD_PARTY_CONTENT"}}})

  info = app_info
  Asc.request!(:patch, "/v1/appInfos/#{info["id"]}", {data: {type: "appInfos", id: info["id"],
    relationships: {primaryCategory: {data: {type: "appCategories", id: "PHOTO_AND_VIDEO"}}}}})
  info_loc = Asc.get!("/v1/appInfos/#{info["id"]}/appInfoLocalizations")["data"].find { |row| row.dig("attributes", "locale") == LOCALE }
  Asc.request!(:patch, "/v1/appInfoLocalizations/#{info_loc["id"]}", {data: {type: "appInfoLocalizations", id: info_loc["id"], attributes: INFO}})
  puts "App info: category, name, subtitle, privacy URL."

  age_rating(info)
  price
  availability

  v = version
  Asc.request!(:patch, "/v1/appStoreVersions/#{v["id"]}", {data: {type: "appStoreVersions", id: v["id"],
    attributes: {copyright: "#{Time.now.year} Urcalab", releaseType: "AFTER_APPROVAL"}}})
  loc = Asc.get!("/v1/appStoreVersions/#{v["id"]}/appStoreVersionLocalizations")["data"].find { |row| row.dig("attributes", "locale") == LOCALE }
  Asc.request!(:patch, "/v1/appStoreVersionLocalizations/#{loc["id"]}", {data: {type: "appStoreVersionLocalizations", id: loc["id"], attributes: VERSION}})
  puts "Version #{v.dig("attributes", "versionString")}: texts, copyright, release after approval."

  review_detail(v)
  screenshots(loc)
end

# Copied from Chao 600 (approved 4+, same profile: no objectionable content, no web access, nothing
# shared with other users), so the field list follows whatever Apple's questionnaire has today.
CHAO600_APP_ID = "6820609522"

def age_rating(info)
  declaration = Asc.get!("/v1/appInfos/#{info["id"]}/ageRatingDeclaration")["data"]
  source_info = Asc.get!("/v1/apps/#{CHAO600_APP_ID}/appInfos")["data"].first
  source = Asc.get!("/v1/appInfos/#{source_info["id"]}/ageRatingDeclaration")["data"]["attributes"]
  attributes = source.reject { |key, value| value.nil? || key == "ageRatingOverride" }
  Asc.request!(:patch, "/v1/ageRatingDeclarations/#{declaration["id"]}", {data: {type: "ageRatingDeclarations", id: declaration["id"], attributes: attributes}})
  puts "Age rating: same answers as Chao 600."
end

def price
  points = Asc.get!("/v1/apps/#{APP_ID}/appPricePoints?filter[territory]=USA&limit=200")["data"]
  free = points.find { |row| row.dig("attributes", "customerPrice").to_f.zero? } or abort "No free price point"
  Asc.request!(:post, "/v1/appPriceSchedules", {
    data: {type: "appPriceSchedules",
      relationships: {
        app: {data: {type: "apps", id: APP_ID}},
        baseTerritory: {data: {type: "territories", id: "USA"}},
        manualPrices: {data: [{type: "appPrices", id: "${free}"}]}
      }},
    included: [{type: "appPrices", id: "${free}",
      attributes: {startDate: nil},
      relationships: {appPricePoint: {data: {type: "appPricePoints", id: free["id"]}}}}]
  })
  puts "Price: free."
end

def availability
  status, = Asc.call(:get, "/v1/apps/#{APP_ID}/appAvailabilityV2")
  if status == 200
    puts "Availability: already set."
    return
  end
  territories = []
  url = "/v1/territories?limit=200"
  while url
    page = Asc.get!(url)
    territories.concat(page["data"].map { |row| row["id"] })
    url = page.dig("links", "next")
  end
  Asc.request!(:post, "/v2/appAvailabilities", {
    data: {type: "appAvailabilities", attributes: {availableInNewTerritories: true},
      relationships: {
        app: {data: {type: "apps", id: APP_ID}},
        territoryAvailabilities: {data: territories.map { |id| {type: "territoryAvailabilities", id: "${#{id}}"} }}
      }},
    included: territories.map { |id|
      {type: "territoryAvailabilities", id: "${#{id}}", attributes: {available: true},
       relationships: {territory: {data: {type: "territories", id: id}}}}
    }
  })
  puts "Availability: #{territories.size} territories."
end

# Contact details come from another app of the team (Chao 600), like the Wave TestFlight scripts do.
def review_detail(v)
  contact_keys = %w[contactFirstName contactLastName contactPhone contactEmail]
  contact = nil
  Asc.get!("/v1/apps?limit=50")["data"].each do |other|
    next if other["id"] == APP_ID

    other_version = Asc.get!("/v1/apps/#{other["id"]}/appStoreVersions?limit=1")["data"].first or next
    status, detail = Asc.call(:get, "/v1/appStoreVersions/#{other_version["id"]}/appStoreReviewDetail")
    next unless status == 200 && detail["data"]

    candidate = detail["data"]["attributes"].slice(*contact_keys)
    if contact_keys.all? { |key| !candidate[key].to_s.empty? }
      contact = candidate
      break
    end
  end
  abort "No review contact details found in other apps" unless contact

  attributes = contact.merge("demoAccountRequired" => false, "notes" => REVIEW_NOTES)
  status, existing = Asc.call(:get, "/v1/appStoreVersions/#{v["id"]}/appStoreReviewDetail")
  if status == 200 && existing["data"]
    Asc.request!(:patch, "/v1/appStoreReviewDetails/#{existing["data"]["id"]}", {data: {type: "appStoreReviewDetails", id: existing["data"]["id"], attributes: attributes}})
  else
    Asc.request!(:post, "/v1/appStoreReviewDetails", {data: {type: "appStoreReviewDetails", attributes: attributes,
      relationships: {appStoreVersion: {data: {type: "appStoreVersions", id: v["id"]}}}}})
  end
  puts "Review details: contact and notes."
end

# 6.9" iPhone (1320 × 2868). Replaces whatever the set had.
def screenshots(loc)
  sets = Asc.get!("/v1/appStoreVersionLocalizations/#{loc["id"]}/appScreenshotSets")["data"]
  set = sets.find { |row| row.dig("attributes", "screenshotDisplayType") == "APP_IPHONE_67" }
  set ||= Asc.request!(:post, "/v1/appScreenshotSets", {data: {type: "appScreenshotSets", attributes: {screenshotDisplayType: "APP_IPHONE_67"},
    relationships: {appStoreVersionLocalization: {data: {type: "appStoreVersionLocalizations", id: loc["id"]}}}}})["data"]
  Asc.get!("/v1/appScreenshotSets/#{set["id"]}/appScreenshots")["data"].each { |shot| Asc.request!(:delete, "/v1/appScreenshots/#{shot["id"]}") }

  SCREENSHOTS.each do |path|
    bytes = File.binread(path)
    shot = Asc.request!(:post, "/v1/appScreenshots", {data: {type: "appScreenshots",
      attributes: {fileName: File.basename(path), fileSize: bytes.bytesize},
      relationships: {appScreenshotSet: {data: {type: "appScreenshotSets", id: set["id"]}}}}})["data"]
    shot.dig("attributes", "uploadOperations").each do |operation|
      uri = URI(operation["url"])
      request = Net::HTTP.const_get(operation["method"].capitalize).new(uri)
      operation["requestHeaders"].each { |header| request[header["name"]] = header["value"] }
      request.body = bytes.byteslice(operation["offset"], operation["length"])
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(request) }
      abort "Screenshot upload failed (#{response.code})" unless response.code.to_i.between?(200, 299)
    end
    Asc.request!(:patch, "/v1/appScreenshots/#{shot["id"]}", {data: {type: "appScreenshots", id: shot["id"],
      attributes: {uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes)}}})
  end
  puts "Screenshots: #{SCREENSHOTS.size} uploaded."
end

def submit(build_number)
  v = version
  builds = Asc.get!("/v1/builds?filter[app]=#{APP_ID}&sort=-uploadedDate&limit=10")["data"]
  build = build_number ? builds.find { |row| row.dig("attributes", "version") == build_number } : builds.first
  abort "Build #{build_number || "(latest)"} not found" unless build
  abort "Build #{build.dig("attributes", "version")} is #{build.dig("attributes", "processingState")}" unless build.dig("attributes", "processingState") == "VALID"

  Asc.request!(:patch, "/v1/appStoreVersions/#{v["id"]}/relationships/build", {data: {type: "builds", id: build["id"]}})
  puts "Version #{v.dig("attributes", "versionString")} uses build #{build.dig("attributes", "version")}."

  submission = Asc.get!("/v1/reviewSubmissions?filter[app]=#{APP_ID}&filter[state]=READY_FOR_REVIEW")["data"].first
  submission ||= Asc.request!(:post, "/v1/reviewSubmissions", {data: {type: "reviewSubmissions", attributes: {platform: "IOS"},
    relationships: {app: {data: {type: "apps", id: APP_ID}}}}})["data"]
  items = Asc.get!("/v1/reviewSubmissions/#{submission["id"]}/items")["data"]
  if items.empty?
    Asc.request!(:post, "/v1/reviewSubmissionItems", {data: {type: "reviewSubmissionItems",
      relationships: {reviewSubmission: {data: {type: "reviewSubmissions", id: submission["id"]}},
                      appStoreVersion: {data: {type: "appStoreVersions", id: v["id"]}}}}})
  end
  Asc.request!(:patch, "/v1/reviewSubmissions/#{submission["id"]}", {data: {type: "reviewSubmissions", id: submission["id"], attributes: {submitted: true}}})
  puts "Submitted for review."
end

case ARGV[0]
when "metadata" then metadata
when "submit" then submit(ARGV[1])
else abort "usage: ruby appstore/asc.rb metadata | submit [build]"
end
