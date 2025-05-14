# NVIDIA DPF Documentation on Netlify

This repository contains documentation for the NVIDIA DPF (DOCA Platform Framework) integration with OpenShift, deployed to Netlify for easy access.

## Documentation Site

The documentation is available at: [openshift-dpf.netlify.app](https://openshift-dpf.netlify.app) (or your custom domain once configured)

## How It Works

### Deployment Architecture

The documentation site uses:

- **MkDocs**: Documentation generator with Markdown support
- **Material for MkDocs**: Modern theme with excellent navigation
- **Netlify**: Hosting platform with continuous deployment
- **GitHub**: Repository for source files

### Continuous Deployment

The documentation site is set up for continuous deployment:

1. Changes pushed to the `docs/update-doca-services` branch trigger a new build
2. Netlify pulls the latest changes from GitHub
3. Netlify builds the documentation using MkDocs
4. The new version is automatically deployed

This setup ensures that documentation is always up to date with the code.

## Making Updates

To update the documentation:

1. Clone the repository
   ```bash
   git clone https://github.com/szigmon/openshift-dpf.git
   cd openshift-dpf
   ```

2. Switch to the documentation branch
   ```bash
   git checkout docs/update-doca-services
   ```

3. Make your changes to the markdown files in the `docs/` directory

4. Build and preview locally
   ```bash
   mkdocs serve
   ```

5. Commit and push your changes
   ```bash
   git add .
   git commit -m "Documentation update: [brief description]"
   git push
   ```

6. Netlify will automatically deploy the updated documentation

## Documentation Structure

The documentation is organized as follows:

- `docs/` - Markdown source files
- `mkdocs.yml` - MkDocs configuration
- `netlify.toml` - Netlify build configuration
- `site/` - Generated HTML (not committed to git)

## Initial Setup Process

The documentation site was set up with these steps:

1. Added MkDocs configuration (`mkdocs.yml`)
2. Created Netlify configuration (`netlify.toml`)
3. Connected the GitHub repository to Netlify
4. Configured build settings on Netlify
5. Set up continuous deployment from the documentation branch

## Troubleshooting

If you encounter build issues:

1. Check the build logs on Netlify
2. Verify your changes build locally with `mkdocs build`
3. Check for missing dependencies in `netlify.toml`
4. Ensure all links between pages are correct 