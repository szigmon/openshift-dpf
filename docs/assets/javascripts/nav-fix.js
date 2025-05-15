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
      
      // Detect if we're on Netlify
      const isNetlify = window.location.hostname.includes('netlify.app');
      console.log("Is Netlify:", isNetlify);
      
      // Map of parent tab text to first child page (filename only)
      const tabRedirects = {
        'Getting Started': 'introduction',
        'Installation': 'full-installation',
        'Operations': 'troubleshooting',
        'Reference': 'automation-reference'
      };
      
      // Function to get the correct URL for a page
      function getPageUrl(pageName) {
        // For Netlify, we need to use a different path structure
        if (isNetlify) {
          return `/${pageName}/`;
        } else {
          return `${pageName}.html`;
        }
      }
      
      // Fix each tab's link
      navTabs.forEach(function(tab) {
        const tabLink = tab.querySelector('.md-tabs__link');
        const tabText = tabLink ? tabLink.textContent.trim() : '';
        console.log("Tab text:", tabText);
        
        if (tabLink && tabRedirects[tabText]) {
          const pageUrl = getPageUrl(tabRedirects[tabText]);
          console.log(`Setting ${tabText} link to ${pageUrl}`);
          tabLink.href = pageUrl;
          
          // Add click handler as backup
          tabLink.addEventListener('click', function(e) {
            console.log(`Redirecting to ${pageUrl}`);
            window.location.href = pageUrl;
            e.preventDefault();
            return false;
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
          const pageUrl = getPageUrl(tabRedirects[parentText]);
          console.log(`Adding click handler for ${parentText} to ${pageUrl}`);
          
          // Create a click handler to navigate to the first child
          parent.addEventListener('click', function(e) {
            console.log(`Sidebar redirecting to ${pageUrl}`);
            window.location.href = pageUrl;
            e.preventDefault();
            return false;
          });
          
          // Also add data attribute for debugging
          parent.dataset.fixedNavigation = "true";
          
          // Create a wrapping link element
          const wrapperLink = document.createElement('a');
          wrapperLink.href = pageUrl;
          wrapperLink.className = 'md-nav__force-link';
          
          // Apply some basic styling to make it cover the parent element
          wrapperLink.style.position = 'absolute';
          wrapperLink.style.top = '0';
          wrapperLink.style.left = '0';
          wrapperLink.style.width = '100%';
          wrapperLink.style.height = '100%';
          wrapperLink.style.zIndex = '1';
          
          // Insert before the parent to ensure clicks work
          parent.parentNode.style.position = 'relative';
          parent.parentNode.insertBefore(wrapperLink, parent);
          
          // Add click handler to the wrapper link
          wrapperLink.addEventListener('click', function(e) {
            console.log(`Wrapper redirecting to ${pageUrl}`);
            window.location.href = pageUrl;
          });
        }
      });
      
      // Directly fix any top-level navigation links
      document.querySelectorAll('.md-tabs__link').forEach(function(link) {
        const linkText = link.textContent.trim();
        if (tabRedirects[linkText]) {
          const pageUrl = getPageUrl(tabRedirects[linkText]);
          console.log(`Direct fix for ${linkText} tab link to ${pageUrl}`);
          link.href = pageUrl;
          
          // Add click event listener with higher priority
          link.addEventListener('click', function(e) {
            console.log(`Direct click on ${linkText} redirecting to ${pageUrl}`);
            window.location.href = pageUrl;
            e.preventDefault();
            return false;
          }, true);
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