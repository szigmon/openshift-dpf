document.addEventListener('DOMContentLoaded', function() {
  // Log for debugging
  console.log("Navigation fix script loaded");
  
  // Navigation tab fixes
  function fixNavigation() {
    console.log("Running navigation fix");
    
    // Wait for navigation elements to be loaded
    setTimeout(function() {
      // Get all main navigation tabs
      const navTabs = document.querySelectorAll('.md-tabs__item');
      console.log("Found nav tabs:", navTabs.length);
      
      // Map of parent tab text to first child URL
      const tabRedirects = {
        'Getting Started': 'introduction.html',
        'Installation': 'full-installation.html',
        'Operations': 'troubleshooting.html',
        'Reference': 'automation-reference.html'
      };
      
      // Fix each tab's link
      navTabs.forEach(function(tab) {
        const tabLink = tab.querySelector('.md-tabs__link');
        const tabText = tabLink ? tabLink.textContent.trim() : '';
        console.log("Tab text:", tabText);
        
        if (tabLink && tabRedirects[tabText]) {
          console.log(`Setting ${tabText} link to ${tabRedirects[tabText]}`);
          tabLink.href = tabRedirects[tabText];
          
          // Add click handler as backup
          tabLink.addEventListener('click', function(e) {
            window.location.href = tabRedirects[tabText];
            e.preventDefault();
          });
        }
      });
      
      // Also fix sidebar navigation parent items
      const sidebarParents = document.querySelectorAll('.md-nav__link[for^="__nav_"]');
      console.log("Found sidebar parents:", sidebarParents.length);
      
      sidebarParents.forEach(function(parent) {
        // Find the parent text
        const parentText = parent.textContent.trim();
        console.log("Sidebar parent:", parentText);
        
        if (tabRedirects[parentText]) {
          console.log(`Adding click handler for ${parentText}`);
          
          // Create a click handler to navigate to the first child
          parent.addEventListener('click', function(e) {
            window.location.href = tabRedirects[parentText];
            e.preventDefault();
          });
          
          // Also add data attribute for debugging
          parent.dataset.fixedNavigation = "true";
          
          // Create a wrapping link element
          const wrapperLink = document.createElement('a');
          wrapperLink.href = tabRedirects[parentText];
          wrapperLink.className = 'md-nav__force-link';
          
          // Apply some basic styling to make it cover the parent element
          wrapperLink.style.position = 'absolute';
          wrapperLink.style.top = '0';
          wrapperLink.style.left = '0';
          wrapperLink.style.width = '100%';
          wrapperLink.style.height = '100%';
          wrapperLink.style.zIndex = '1';
          wrapperLink.style.opacity = '0.5';
          
          // Insert before the parent to ensure clicks work
          parent.parentNode.style.position = 'relative';
          parent.parentNode.insertBefore(wrapperLink, parent);
        }
      });
      
      // Directly fix any top-level navigation links
      document.querySelectorAll('.md-tabs__link').forEach(function(link) {
        const linkText = link.textContent.trim();
        if (tabRedirects[linkText]) {
          console.log(`Direct fix for ${linkText} tab link`);
          link.href = tabRedirects[linkText];
        }
      });
    }, 300); // Increase delay to ensure DOM is ready
  }
  
  // Run fix on page load
  fixNavigation();
  
  // Also run after a short delay to ensure everything is loaded
  setTimeout(fixNavigation, 1000);
  
  // Run fix again if spa navigation occurs (material theme sometimes uses this)
  window.addEventListener('navigation', fixNavigation);
}); 