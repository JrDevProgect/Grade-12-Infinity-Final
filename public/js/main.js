document.addEventListener('DOMContentLoaded', () => {
  initMobileMenu();
  initFormHandlers();
  initFilePreview();
  initAnimations();
});

function initMobileMenu() {
  const menuToggle = document.querySelector('.mobile-menu-toggle');
  const mainNav = document.querySelector('.main-nav');
  
  if (!menuToggle || !mainNav) return;
  
  menuToggle.addEventListener('click', () => {
    mainNav.classList.toggle('active');
    document.body.classList.toggle('menu-open');
    
    const spans = menuToggle.querySelectorAll('span');
    spans[0].style.transform = mainNav.classList.contains('active') ? 'rotate(45deg) translate(5px, 5px)' : '';
    spans[1].style.opacity = mainNav.classList.contains('active') ? '0' : '1';
    spans[2].style.transform = mainNav.classList.contains('active') ? 'rotate(-45deg) translate(5px, -5px)' : '';
  });
  
  document.addEventListener('click', (e) => {
    if (mainNav.classList.contains('active') && !e.target.closest('.main-nav') && !e.target.closest('.mobile-menu-toggle')) {
      mainNav.classList.remove('active');
      document.body.classList.remove('menu-open');
      
      const spans = menuToggle.querySelectorAll('span');
      spans[0].style.transform = '';
      spans[1].style.opacity = '1';
      spans[2].style.transform = '';
    }
  });
}

function initFormHandlers() {
  setupFormSubmission('login-form', '/admin/login', 'POST');
  setupFormSubmission('student-form', '/admin/students', 'POST');
  setupFormSubmission('teacher-form', '/admin/teachers', 'POST');
  setupFormSubmission('gallery-form', '/admin/gallery', 'POST', true);
}

function setupFormSubmission(formId, endpoint, method, isMultipart = false) {
  const form = document.getElementById(formId);
  if (!form) return;
  
  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    
    const submitBtn = form.querySelector('button[type="submit"]');
    const spinner = submitBtn?.querySelector('.spinner');
    const errorElement = document.getElementById(`${formId.split('-')[0]}-error`);
    
    if (spinner) spinner.classList.remove('hidden');
    if (errorElement) errorElement.classList.add('hidden');
    if (submitBtn) submitBtn.disabled = true;
    
    try {
      let response;
      
      if (isMultipart) {
        const formData = new FormData(form);
        response = await fetch(endpoint, {
          method,
          body: formData,
          headers: {
            'Authorization': `Bearer ${localStorage.getItem('token')}`
          }
        });
      } else {
        const formData = new FormData(form);
        const data = Object.fromEntries(formData.entries());
        
        response = await fetch(endpoint, {
          method,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `Bearer ${localStorage.getItem('token')}`
          },
          body: JSON.stringify(data)
        });
      }
      
      const result = await response.json();
      
      if (response.ok) {
        if (formId === 'login-form') {
          localStorage.setItem('token', result.token);
          window.location.href = '/admin/panel';
        } else {
          form.reset();
          
          if (formId === 'gallery-form') {
            const filePreview = form.querySelector('.file-preview');
            if (filePreview) filePreview.innerHTML = '';
          }
          
          showNotification('Success!', result.message || 'Operation completed successfully.');
          
          setTimeout(() => {
            window.location.reload();
          }, 1500);
        }
      } else {
        throw new Error(result.error || 'Something went wrong');
      }
    } catch (error) {
      if (errorElement) {
        errorElement.textContent = error.message;
        errorElement.classList.remove('hidden');
      }
    } finally {
      if (spinner) spinner.classList.add('hidden');
      if (submitBtn) submitBtn.disabled = false;
    }
  });
}

function initFilePreview() {
  const fileInput = document.getElementById('gallery-image');
  const filePreview = document.querySelector('.file-preview');
  
  if (!fileInput || !filePreview) return;
  
  fileInput.addEventListener('change', () => {
    filePreview.innerHTML = '';
    
    if (fileInput.files && fileInput.files[0]) {
      const reader = new FileReader();
      
      reader.onload = (e) => {
        const img = document.createElement('img');
        img.src = e.target.result;
        img.alt = 'Image Preview';
        filePreview.appendChild(img);
      };
      
      reader.readAsDataURL(fileInput.files[0]);
    }
  });
}

function initAnimations() {
  const animatedElements = document.querySelectorAll('[data-aos]');
  
  if (animatedElements.length === 0) return;
  
  const observer = new IntersectionObserver((entries) => {
    entries.forEach(entry => {
      if (entry.isIntersecting) {
        entry.target.classList.add('aos-animate');
        observer.unobserve(entry.target);
      }
    });
  }, { threshold: 0.1 });
  
  animatedElements.forEach(element => {
    element.classList.add('aos-init');
    observer.observe(element);
  });
}

function showNotification(title, message) {
  const notification = document.createElement('div');
  notification.className = 'notification';
  notification.innerHTML = `
    <div class="notification-content">
      <h4>${title}</h4>
      <p>${message}</p>
    </div>
  `;
  
  document.body.appendChild(notification);
  
  setTimeout(() => {
    notification.classList.add('show');
  }, 10);
  
  setTimeout(() => {
    notification.classList.remove('show');
    setTimeout(() => {
      notification.remove();
    }, 300);
  }, 3000);
}

document.addEventListener('DOMContentLoaded', () => {
  const style = document.createElement('style');
  style.textContent = `
    .notification {
      position: fixed;
      top: 20px;
      right: 20px;
      background-color: var(--color-primary);
      color: white;
      padding: 1rem;
      border-radius: 4px;
      box-shadow: var(--shadow-md);
      z-index: 1000;
      transform: translateX(120%);
      transition: transform 0.3s ease;
    }
    
    .notification.show {
      transform: translateX(0);
    }
    
    .notification h4 {
      margin-bottom: 0.5rem;
    }
    
    .notification p {
      margin: 0;
      font-size: 0.9rem;
    }
    
    .aos-init {
      opacity: 0;
      transform: translateY(20px);
      transition: opacity 0.8s ease, transform 0.8s ease;
    }
    
    .aos-animate {
      opacity: 1;
      transform: translateY(0);
    }
    
    [data-aos="fade-right"] {
      transform: translateX(-20px);
    }
    
    [data-aos="fade-left"] {
      transform: translateX(20px);
    }
    
    [data-aos="zoom-in"] {
      transform: scale(0.9);
    }
    
    [data-aos="fade-right"].aos-animate,
    [data-aos="fade-left"].aos-animate {
      transform: translateX(0);
    }
    
    [data-aos="zoom-in"].aos-animate {
      transform: scale(1);
    }
    
    [data-aos-delay="100"] {
      transition-delay: 0.1s;
    }
    
    [data-aos-delay="200"] {
      transition-delay: 0.2s;
    }
  `;
  
  document.head.appendChild(style);
});
