# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/channels", under: "channels"
pin "@xterm/xterm", to: "@xterm--xterm.js" # @6.0.0
pin "@xterm/addon-clipboard", to: "@xterm--addon-clipboard.js" # @0.2.0
pin "@xterm/addon-fit", to: "@xterm--addon-fit.js" # @0.11.0
pin "@xterm/addon-web-links", to: "@xterm--addon-web-links.js" # @0.12.0
