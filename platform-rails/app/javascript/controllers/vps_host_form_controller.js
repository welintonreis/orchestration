import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "authMethod",
    "savedCredSection",
    "directSecretSection",
    "directSecretLabel",
    "directSecretInput",
    "directSecretHint",
    "passphraseSection"
  ]

  connect() {
    this.toggle()
  }

  toggle() {
    const method = this.authMethodTarget.value
    const isKey = method === "key" || method === "key_with_passphrase"
    const isPassphrase = method === "key_with_passphrase"

    if (this.hasPassphraseSectionTarget) {
      this.passphraseSectionTarget.classList.toggle("hidden", !isPassphrase)
    }

    if (this.hasDirectSecretLabelTarget) {
      this.directSecretLabelTarget.textContent = isKey ? "Chave Privada SSH (OpenSSH / PEM)" : "Senha SSH"
    }

    if (this.hasDirectSecretInputTarget) {
      this.directSecretInputTarget.placeholder = isKey
        ? "-----BEGIN OPENSSH PRIVATE KEY-----\n..."
        : "Digite a senha do host…"
    }

    if (this.hasDirectSecretHintTarget) {
      this.directSecretHintTarget.textContent = isKey
        ? "Cole o conteúdo da sua chave privada (ex: ~/.ssh/id_ed25519 ou id_rsa). Ela será criptografada com segurança."
        : "A senha será criptografada e armazenada de forma segura."
    }
  }

  setSource(event) {
    const source = event.target.value
    if (this.hasSavedCredSectionTarget) {
      this.savedCredSectionTarget.classList.toggle("hidden", source !== "saved")
    }
    if (this.hasDirectSecretSectionTarget) {
      this.directSecretSectionTarget.classList.toggle("hidden", source !== "direct")
    }
  }
}
