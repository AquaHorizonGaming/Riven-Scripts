#!/usr/bin/env bash

select_scraper() {
  banner 'Scraper Selection (REQUIRED)'

  echo 'Choose ONE scraping backend:'
  echo
  echo '1) Torrentio   (No config required)'
  echo '2) Prowlarr    (Local instance only)'
  echo '3) Comet       (Public or self-hosted)'
  echo '4) Jackett     (Local instance only)'
  echo '5) Zilean      (Public or self-hosted)'
  echo

  read -r -p 'Select ONE: ' SCR_SEL

  RIVEN_SCRAPING_TORRENTIO_ENABLED=false
  RIVEN_SCRAPING_PROWLARR_ENABLED=false
  RIVEN_SCRAPING_COMET_ENABLED=false
  RIVEN_SCRAPING_JACKETT_ENABLED=false
  RIVEN_SCRAPING_ZILEAN_ENABLED=false

  RIVEN_SCRAPING_PROWLARR_URL=''
  RIVEN_SCRAPING_PROWLARR_API_KEY=''
  RIVEN_SCRAPING_COMET_URL=''
  RIVEN_SCRAPING_JACKETT_URL=''
  RIVEN_SCRAPING_JACKETT_API_KEY=''
  RIVEN_SCRAPING_ZILEAN_URL=''

  case "$SCR_SEL" in
    1)
      RIVEN_SCRAPING_TORRENTIO_ENABLED=true
      echo
      echo 'Torrentio selected.'
      echo '• Uses public Torrentio endpoint'
      echo '• No configuration required'
      ;;
    2)
      RIVEN_SCRAPING_PROWLARR_ENABLED=true
      echo
      echo 'Prowlarr selected.'
      echo
      echo 'Example:'
      echo '  • http://localhost:9696'
      echo
      echo 'API Key location:'
      echo '  Settings → General → API Key'
      echo
      RIVEN_SCRAPING_PROWLARR_URL="$(require_url 'Enter Prowlarr URL')"
      RIVEN_SCRAPING_PROWLARR_API_KEY="$(read_masked_non_empty 'Enter Prowlarr API Key')"
      ;;
    3)
      RIVEN_SCRAPING_COMET_ENABLED=true
      echo
      echo 'Comet selected.'
      echo
      echo 'Examples:'
      echo '  • Public: https://cometfortheweebs.midnightignite.me'
      echo '  • Local:  http://localhost:<port>'
      echo
      echo 'No API key is required.'
      echo
      RIVEN_SCRAPING_COMET_URL="$(require_url 'Enter Comet base URL')"
      ;;
    4)
      RIVEN_SCRAPING_JACKETT_ENABLED=true
      echo
      echo 'Jackett selected.'
      echo
      echo 'Example:'
      echo '  • http://localhost:9117'
      echo
      echo 'API Key location:'
      echo '  Jackett Web UI → Top-right corner'
      echo
      RIVEN_SCRAPING_JACKETT_URL="$(require_url 'Enter Jackett URL')"
      RIVEN_SCRAPING_JACKETT_API_KEY="$(read_masked_non_empty 'Enter Jackett API Key')"
      ;;
    5)
      RIVEN_SCRAPING_ZILEAN_ENABLED=true
      echo
      echo 'Zilean selected.'
      echo
      echo 'Examples:'
      echo '  • Public: https://zilean.example.com'
      echo '  • Local:  http://localhost:<port>'
      echo
      echo 'No API key is required.'
      echo
      RIVEN_SCRAPING_ZILEAN_URL="$(require_url 'Enter Zilean base URL')"
      ;;
    *)
      fail 'Scraper selection REQUIRED'
      ;;
  esac
}
