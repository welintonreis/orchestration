(function () {
  var modal    = null;
  var message  = null;
  var btnOk    = null;
  var btnCancel= null;
  var backdrop = null;

  function getEls() {
    modal    = document.getElementById('confirm-modal');
    message  = document.getElementById('confirm-message');
    btnOk    = document.getElementById('confirm-ok');
    btnCancel= document.getElementById('confirm-cancel');
    backdrop = document.getElementById('confirm-backdrop');
  }

  function showConfirm(msg) {
    getEls();
    if (!modal) return Promise.resolve(window.confirm(msg));
    return new Promise(function (resolve) {
      message.textContent = msg;
      modal.classList.remove('hidden');

      function cleanup(result) {
        modal.classList.add('hidden');
        btnOk.removeEventListener('click', onOk);
        btnCancel.removeEventListener('click', onCancel);
        backdrop.removeEventListener('click', onCancel);
        resolve(result);
      }
      function onOk()     { cleanup(true);  }
      function onCancel() { cleanup(false); }

      btnOk.addEventListener('click', onOk);
      btnCancel.addEventListener('click', onCancel);
      backdrop.addEventListener('click', onCancel);
    });
  }

  function setConfirm() {
    if (!window.Turbo) return;
    if (Turbo.config && Turbo.config.forms) {
      Turbo.config.forms.confirm = showConfirm;
    } else {
      Turbo.setConfirmMethod(showConfirm);
    }
  }

  // Destroy Alpine components before Turbo swaps body — prevents stale scope errors (perPage undefined etc.)
  document.addEventListener('turbo:before-render', function () {
    if (window.Alpine) {
      window.Alpine.destroyTree(document.body);
    }
  });

  document.addEventListener('turbo:load', setConfirm);
  document.addEventListener('DOMContentLoaded', setConfirm);
})();
