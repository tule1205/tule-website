(function () {
  const form = document.getElementById("signup-form");
  if (!form) return;

  const nameInput = document.getElementById("name");
  const emailInput = document.getElementById("email");
  const messageInput = document.getElementById("message");
  const honeypotInput = document.getElementById("company");

  const nameError = document.getElementById("name-error");
  const emailError = document.getElementById("email-error");
  const messageError = document.getElementById("message-error");
  const status = document.getElementById("form-status");
  const submitBtn = form.querySelector(".submit-btn");

  let supabase = null;
  try {
    if (window.supabase && typeof window.supabase.createClient === "function") {
      supabase = window.supabase.createClient(
        "https://pirjcacaiugtspgvjzsk.supabase.co",
        "sb_publishable_iyAQKNTsybF5cx3PL915Mw_fK0HxPTK"
      );
    } else {
      console.error(
        "Supabase client library not loaded. Make sure the CDN <script> tag is in <head> of homepage.html and there is no network/ad-blocker blocking jsdelivr."
      );
    }
  } catch (err) {
    console.error("Failed to initialize Supabase client:", err);
  }

  const NAME_MAX = 200;
  const EMAIL_MAX = 320;
  const MESSAGE_MIN = 5;
  const MESSAGE_MAX = 1000;

  const nameRegex = /^[\p{L}\p{M}'\-.\s]+$/u;
  const emailRegex = /^[^\s@<>"']+@[^\s@<>"'.]+(?:\.[^\s@<>"'.]+)+$/;

  function validateName(value) {
    const v = value.trim();
    if (!v) return "Please enter your name.";
    if (v.length > NAME_MAX) return `Name must be ${NAME_MAX} characters or fewer.`;
    if (!nameRegex.test(v)) return "Name contains invalid characters.";
    return "";
  }

  function validateEmail(value) {
    const v = value.trim();
    if (!v) return "Please enter your email.";
    if (v.length > EMAIL_MAX) return `Email must be ${EMAIL_MAX} characters or fewer.`;
    if (!emailRegex.test(v)) return "Please enter a valid email address.";
    return "";
  }

  function validateMessage(value) {
    const v = value.trim();
    if (!v) return "Please enter a message.";
    if (v.length < MESSAGE_MIN) return `Message must be at least ${MESSAGE_MIN} characters.`;
    if (v.length > MESSAGE_MAX) return `Message must be ${MESSAGE_MAX} characters or fewer.`;
    return "";
  }

  function showError(input, errorEl, message) {
    errorEl.textContent = message;
    input.style.borderColor = message ? "#b00020" : "#d0d0d0";
  }

  nameInput.addEventListener("input", () =>
    showError(nameInput, nameError, validateName(nameInput.value))
  );
  emailInput.addEventListener("input", () =>
    showError(emailInput, emailError, validateEmail(emailInput.value))
  );
  messageInput.addEventListener("input", () =>
    showError(messageInput, messageError, validateMessage(messageInput.value))
  );

  form.addEventListener("submit", async function (e) {
    e.preventDefault();
    status.textContent = "";

    if (honeypotInput && honeypotInput.value.trim() !== "") {
      status.style.color = "#0a7d3b";
      status.textContent = "Thanks! Your message has been received.";
      form.reset();
      return;
    }

    const nMsg = validateName(nameInput.value);
    const eMsg = validateEmail(emailInput.value);
    const mMsg = validateMessage(messageInput.value);

    showError(nameInput, nameError, nMsg);
    showError(emailInput, emailError, eMsg);
    showError(messageInput, messageError, mMsg);

    if (nMsg || eMsg || mMsg) {
      status.style.color = "#b00020";
      status.textContent = "Please fix the errors above and try again.";
      return;
    }

    if (!supabase) {
      status.style.color = "#b00020";
      status.textContent =
        "Service unavailable. Please refresh the page and try again.";
      return;
    }

    const name = nameInput.value.trim().slice(0, NAME_MAX);
    const email = emailInput.value.trim().slice(0, EMAIL_MAX);
    const message = messageInput.value.trim().slice(0, MESSAGE_MAX);

    submitBtn.disabled = true;
    status.style.color = "#1a1a1a";
    status.textContent = "Sending...";

    try {
      const { error } = await supabase.from("contactForm").insert({
        name: name,
        email: email,
        message: message,
      });

      if (error) throw error;

      status.style.color = "#0a7d3b";
      status.textContent = `Thanks, ${name}! Your message has been received.`;
      form.reset();
    } catch (err) {
      console.error("Supabase insert failed:", err);
      status.style.color = "#b00020";
      status.textContent = "Sorry, something went wrong. Please try again.";
    } finally {
      submitBtn.disabled = false;
    }
  });
})();
