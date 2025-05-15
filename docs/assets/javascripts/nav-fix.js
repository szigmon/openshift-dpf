document.addEventListener('DOMContentLoaded', function() {
  // Navigation tab fixes
  function fixNavigation() {
    // Wait for navigation elements to be loaded
    setTimeout(function() {
      // Get all main navigation tabs
      const navTabs = document.querySelectorAll('.md-tabs__item');
      
      // Map of parent tab text to first child URL
      const tabRedirects = {
        'Getting Started': 'introduction.html',
        'Installation': 'full-installation.html',
        'Configuration': 'bfb-image.html',
        'Operations': 'benchmarking.html',
        'Reference': 'automation-reference.html'
      };
      
      // Fix each tab's link
      navTabs.forEach(function(tab) {
        const tabLink = tab.querySelector('.md-tabs__link');
        if (tabLink && tabRedirects[tabLink.textContent.trim()]) {
          tabLink.href = tabRedirects[tabLink.textContent.trim()];
        }
      });
      
      // Also fix sidebar navigation parent items
      const sidebarParents = document.querySelectorAll('.md-nav__link[for^="__nav_"]');
      sidebarParents.forEach(function(parent) {
        // Find the parent text
        const parentText = parent.textContent.trim();
        if (tabRedirects[parentText]) {
          // Create a click handler to navigate to the first child
          parent.addEventListener('click', function(e) {
            if (e.target === parent) {
              window.location.href = tabRedirects[parentText];
              e.preventDefault();
            }
          });
        }
      });
    }, 100);
  }
  
  // Run fix on page load
  fixNavigation();
  
  // Run fix again if spa navigation occurs (material theme sometimes uses this)
  window.addEventListener('navigation', fixNavigation);
}); 