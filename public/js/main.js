document.addEventListener('DOMContentLoaded', () => {
  // Burger menu toggle
  const burger = document.getElementById('burger');
  const mobileNav = document.getElementById('mobile-nav');
  if (burger && mobileNav) {
    burger.addEventListener('click', () => {
      mobileNav.classList.toggle('hidden');
      mobileNav.classList.toggle('animate-leaf-fall');
    });
  }

  // Form submission handler
  const handleFormSubmit = async (formId, spinnerId, errorId, action, method, isMultipart = false) => {
    const form = document.getElementById(formId);
    const spinner = document.getElementById(spinnerId);
    const error = document.getElementById(errorId);
    if (!form) return;

    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      if (spinner) spinner.classList.remove('hidden');
      if (error) error.classList.add('hidden');

      try {
        const formData = isMultipart ? new FormData(form) : new FormData(form);
        const headers = isMultipart ? { 'Authorization': `Bearer ${localStorage.getItem('token')}` } : {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${localStorage.getItem('token')}`
        };
        const body = isMultipart ? formData : JSON.stringify(Object.fromEntries(formData));

        const res = await fetch(action, {
          method,
          headers,
          body
        });

        if (res.ok) {
          if (formId === 'login-form') {
            const { token } = await res.json();
            localStorage.setItem('token', token);
            window.location.href = '/admin/panel';
          } else {
            window.location.reload();
          }
        } else {
          const { error: errMsg } = await res.json();
          if (error) {
            error.textContent = errMsg || 'An error occurred';
            error.classList.remove('hidden');
          }
        }
      } catch (err) {
        if (error) {
          error.textContent = 'Network error, please try again';
          error.classList.remove('hidden');
        }
      } finally {
        if (spinner) spinner.classList.add('hidden');
      }
    });
  };

  // Initialize forms
  handleFormSubmit('login-form', 'login-spinner', 'login-error', '/admin/login', 'POST');
  handleFormSubmit('student-form', 'student-spinner', 'student-error', '/admin/students', 'POST');
  handleFormSubmit('teacher-form', 'teacher-spinner', 'teacher-error', '/admin/teachers', 'POST');
  handleFormSubmit('gallery-form', 'gallery-spinner', 'gallery-error', '/admin/gallery', 'POST', true);
});
