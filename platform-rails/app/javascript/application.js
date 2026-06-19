// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import { Turbo } from "@hotwired/turbo-rails"
import "controllers"

// Wire up the custom confirm modal. Runs after Turbo ESM is ready — no polling needed.
Turbo.config.forms.confirm = function showConfirm(msg) {
  const modal    = document.getElementById("confirm-modal")
  const message  = document.getElementById("confirm-message")
  const btnOk    = document.getElementById("confirm-ok")
  const btnCancel= document.getElementById("confirm-cancel")
  const backdrop = document.getElementById("confirm-backdrop")

  if (!modal) return Promise.resolve(window.confirm(msg))

  return new Promise(function (resolve) {
    message.textContent = msg
    modal.classList.remove("hidden")

    function cleanup(result) {
      modal.classList.add("hidden")
      btnOk.removeEventListener("click", onOk)
      btnCancel.removeEventListener("click", onCancel)
      backdrop.removeEventListener("click", onCancel)
      resolve(result)
    }
    function onOk()     { cleanup(true)  }
    function onCancel() { cleanup(false) }

    btnOk.addEventListener("click", onOk)
    btnCancel.addEventListener("click", onCancel)
    backdrop.addEventListener("click", onCancel)
  })
}
