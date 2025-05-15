document.addEventListener('DOMContentLoaded', function() {
  // Log for debugging
  console.log("Navigation fix script loaded");
  
  // Fix all links that end with .md
  const mdLinks = document.querySelectorAll('a[href$=".md"]');
  console.log(`Found ${mdLinks.length} links with .md extension`);
  
  mdLinks.forEach(link => {
    // Replace .md with .html extension
    link.href = link.href.replace('.md', '.html');
    console.log(`Fixed MD link: ${link.href}`);
  });
  
  // Navigation tab fixes
  function fixNavigation() {
    console.log("Running navigation fix");
    
    // Wait for navigation elements to be loaded
    setTimeout(function() {
      // Get all main navigation tabs
      const navTabs = document.querySelectorAll('.md-tabs__item');
      console.log("Found nav tabs:", navTabs.length);
      
      // Map of parent tab text to first child page (filename only)
      // Make sure these files actually exist and have the correct content
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
          const pageUrl = tabRedirects[tabText];
          console.log(`Setting ${tabText} link to ${pageUrl}`);
          
          // Use absolute path to ensure correct navigation
          if (pageUrl.indexOf('/') !== 0) {
            tabLink.href = '/' + pageUrl;
          } else {
            tabLink.href = pageUrl;
          }
          
          // Add click handler as backup
          tabLink.addEventListener('click', function(e) {
            // Use direct window location for most reliable navigation
            const targetUrl = window.location.origin + '/' + pageUrl;
            console.log(`Redirecting to ${targetUrl}`);
            window.location.href = targetUrl;
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
          const pageUrl = tabRedirects[parentText];
          console.log(`Adding click handler for ${parentText} to ${pageUrl}`);
          
          // Create a click handler to navigate to the first child
          parent.addEventListener('click', function(e) {
            const targetUrl = window.location.origin + '/' + pageUrl;
            console.log(`Sidebar redirecting to ${targetUrl}`);
            window.location.href = targetUrl;
            e.preventDefault();
            return false;
          });
          
          // Also add data attribute for debugging
          parent.dataset.fixedNavigation = "true";
          
          // Create a wrapping link element
          const wrapperLink = document.createElement('a');
          wrapperLink.href = '/' + pageUrl;
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
            const targetUrl = window.location.origin + '/' + pageUrl;
            console.log(`Wrapper redirecting to ${targetUrl}`);
            window.location.href = targetUrl;
          });
        }
      });
      
      // Directly fix any top-level navigation links
      document.querySelectorAll('.md-tabs__link').forEach(function(link) {
        const linkText = link.textContent.trim();
        if (tabRedirects[linkText]) {
          const pageUrl = tabRedirects[linkText];
          console.log(`Direct fix for ${linkText} tab link to ${pageUrl}`);
          
          // Use absolute path to ensure correct navigation
          if (pageUrl.indexOf('/') !== 0) {
            link.href = '/' + pageUrl;
          } else {
            link.href = pageUrl;
          }
          
          // Add click event listener with higher priority
          link.addEventListener('click', function(e) {
            const targetUrl = window.location.origin + '/' + pageUrl;
            console.log(`Direct click on ${linkText} redirecting to ${targetUrl}`);
            window.location.href = targetUrl;
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