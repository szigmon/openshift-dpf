#!/bin/bash

echo "==============================================="
echo "OpenShift DPF Documentation Netlify Deployment"
echo "==============================================="
echo ""
echo "Follow these steps to deploy to Netlify:"
echo ""
echo "1. Go to: https://app.netlify.com/start"
echo "2. Sign in with your preferred method (GitHub recommended)"
echo "3. Click 'Import from Git'"
echo "4. Select GitHub and authorize Netlify"
echo "5. Select the 'szigmon/openshift-dpf' repository"
echo "6. Configure with these settings:"
echo "   - Branch to deploy: docs/update-doca-services"
echo "   - Base directory: (leave empty)"
echo "   - Build command: (leave as default from netlify.toml)"
echo "   - Publish directory: site"
echo "7. Click 'Deploy site'"
echo ""
echo "After deployment, Netlify will give you a random URL. You can customize this"
echo "in the site settings or add a custom domain."
echo ""
echo "To enable continuous deployment:"
echo "- Netlify automatically sets up a webhook in your GitHub repository"
echo "- Any changes pushed to the selected branch will trigger a new build"
echo "- You can configure branch deploy settings in the Build & Deploy settings"
echo ""
echo "Opening Netlify deployment page in your browser..."

# Open the Netlify start page
if [[ "$OSTYPE" == "darwin"* ]]; then
  open "https://app.netlify.com/start"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  xdg-open "https://app.netlify.com/start"
else
  echo "Please visit https://app.netlify.com/start in your browser"
fi 