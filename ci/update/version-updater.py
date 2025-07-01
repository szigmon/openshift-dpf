#!/usr/bin/env python3

"""
Version Updater Script for DPF CI
Updates manifest files with new DPF versions
"""

import os
import sys
import yaml
import json
import argparse
import re
from pathlib import Path
from typing import Dict, List, Tuple
from datetime import datetime

class DPFVersionUpdater:
    def __init__(self, project_root: str):
        self.project_root = Path(project_root)
        self.manifests_dir = self.project_root / 'manifests'
        self.config_path = self.project_root / 'ci' / 'config' / 'versions.yaml'
        self.updates_made = []
        
    def load_config(self) -> dict:
        """Load version configuration"""
        with open(self.config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def save_config(self, config: dict):
        """Save updated version configuration"""
        with open(self.config_path, 'w') as f:
            yaml.dump(config, f, default_flow_style=False, sort_keys=False)
    
    def update_helm_chart_version(self, file_path: Path, new_version: str) -> bool:
        """Update Helm chart version in a service template file"""
        try:
            with open(file_path, 'r') as f:
                data = yaml.safe_load(f)
            
            if not data or 'spec' not in data:
                return False
            
            # Check if this is a service template with helm chart
            if 'helmChart' in data['spec'] and 'source' in data['spec']['helmChart']:
                old_version = data['spec']['helmChart']['source'].get('version', 'unknown')
                
                # Only update if version is different
                if old_version != new_version:
                    data['spec']['helmChart']['source']['version'] = new_version
                    
                    # Write back the updated file
                    with open(file_path, 'w') as f:
                        yaml.dump(data, f, default_flow_style=False, sort_keys=False)
                    
                    self.updates_made.append({
                        'file': str(file_path.relative_to(self.project_root)),
                        'field': 'helmChart.source.version',
                        'old': old_version,
                        'new': new_version
                    })
                    return True
            
            return False
            
        except Exception as e:
            print(f"Error updating {file_path}: {e}")
            return False
    
    def update_image_tags(self, file_path: Path, version_mapping: Dict[str, str]) -> bool:
        """Update container image tags based on version mapping"""
        try:
            with open(file_path, 'r') as f:
                content = f.read()
            
            original_content = content
            updates = 0
            
            # Pattern to match image tags
            # Matches patterns like: image: registry/repo/name:v25.1.1
            pattern = r'(image:\s*[^\s:]+):v\d+\.\d+\.\d+'
            
            def replace_version(match):
                nonlocal updates
                base = match.group(1)
                # Extract the image name to determine which version to use
                for old_ver, new_ver in version_mapping.items():
                    if f":v{old_ver}" in match.group(0):
                        updates += 1
                        return f"{base}:v{new_ver}"
                return match.group(0)
            
            content = re.sub(pattern, replace_version, content)
            
            if content != original_content:
                with open(file_path, 'w') as f:
                    f.write(content)
                
                self.updates_made.append({
                    'file': str(file_path.relative_to(self.project_root)),
                    'field': 'image tags',
                    'updates': updates
                })
                return True
            
            return False
            
        except Exception as e:
            print(f"Error updating images in {file_path}: {e}")
            return False
    
    def update_dpf_operator_config(self, new_version: str) -> bool:
        """Update DPF operator configuration"""
        config_file = self.manifests_dir / 'dpf-installation' / 'dpfoperatorconfig.yaml'
        
        if not config_file.exists():
            print(f"DPF operator config not found: {config_file}")
            return False
        
        try:
            with open(config_file, 'r') as f:
                data = yaml.safe_load(f)
            
            # Update image tag if present
            if 'spec' in data and 'imagePullSpecs' in data['spec']:
                for component, image in data['spec']['imagePullSpecs'].items():
                    if ':v' in image:
                        # Extract current version
                        old_image = image
                        base_image = image.split(':')[0]
                        new_image = f"{base_image}:v{new_version}"
                        
                        data['spec']['imagePullSpecs'][component] = new_image
                        
                        self.updates_made.append({
                            'file': str(config_file.relative_to(self.project_root)),
                            'field': f'imagePullSpecs.{component}',
                            'old': old_image,
                            'new': new_image
                        })
            
            # Write back
            with open(config_file, 'w') as f:
                yaml.dump(data, f, default_flow_style=False, sort_keys=False)
            
            return True
            
        except Exception as e:
            print(f"Error updating DPF operator config: {e}")
            return False
    
    def update_version_files(self, new_version: str, components: List[str] = None) -> Dict:
        """Update all version references in the project"""
        print(f"Updating to DPF version: {new_version}")
        
        # Load current configuration
        config = self.load_config()
        old_version = config['dpf_versions']['current']
        
        # Determine which components to update
        if components is None:
            # Default components that typically follow DPF version
            components = ['ovn-kubernetes', 'flannel']
        
        results = {
            'success': [],
            'failed': [],
            'skipped': []
        }
        
        # Update service templates
        template_files = [
            'ovn-template.yaml',
            'flannel-template.yaml',
            'hbn-template.yaml',
            'blueman-template.yaml',
            'dts-template.yaml'
        ]
        
        for template in template_files:
            file_path = self.manifests_dir / 'post-installation' / template
            
            if not file_path.exists():
                results['skipped'].append(str(file_path))
                continue
            
            # Determine if this component should be updated
            component_name = template.replace('-template.yaml', '')
            
            if component_name in components or component_name == 'ovn':
                # OVN uses 'ovn-kubernetes' in config
                if component_name == 'ovn':
                    component_name = 'ovn-kubernetes'
                
                if self.update_helm_chart_version(file_path, new_version):
                    results['success'].append(str(file_path))
                else:
                    results['failed'].append(str(file_path))
            else:
                results['skipped'].append(str(file_path))
        
        # Update DPF operator config
        if self.update_dpf_operator_config(new_version):
            results['success'].append('dpfoperatorconfig.yaml')
        
        # Update version configuration
        config['dpf_versions']['current'] = new_version
        
        # Add to tested versions if not already there
        if new_version not in config['dpf_versions']['tested']:
            config['dpf_versions']['tested'].insert(0, new_version)
        
        # Update helm chart versions in config
        for component in components:
            if component in config['helm_charts']:
                config['helm_charts'][component]['current'] = new_version
                
                if 'tested' in config['helm_charts'][component]:
                    if new_version not in config['helm_charts'][component]['tested']:
                        config['helm_charts'][component]['tested'].insert(0, new_version)
        
        # Save updated configuration
        self.save_config(config)
        results['success'].append('ci/config/versions.yaml')
        
        return results
    
    def generate_update_report(self) -> str:
        """Generate a report of all updates made"""
        report = []
        report.append("# DPF Version Update Report")
        report.append(f"\nGenerated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        report.append(f"\nTotal updates: {len(self.updates_made)}")
        
        if self.updates_made:
            report.append("\n## Updates Made")
            
            # Group by file
            files = {}
            for update in self.updates_made:
                file_name = update['file']
                if file_name not in files:
                    files[file_name] = []
                files[file_name].append(update)
            
            for file_name, updates in files.items():
                report.append(f"\n### {file_name}")
                for update in updates:
                    if 'old' in update and 'new' in update:
                        report.append(f"- {update['field']}: `{update['old']}` → `{update['new']}`")
                    elif 'updates' in update:
                        report.append(f"- {update['field']}: {update['updates']} updates")
        
        return '\n'.join(report)
    
    def validate_updates(self, dry_run: bool = False) -> bool:
        """Validate that updates are correct"""
        print("\nValidating updates...")
        
        # Check that files are valid YAML after updates
        for update in self.updates_made:
            if 'file' in update:
                file_path = self.project_root / update['file']
                
                if file_path.suffix in ['.yaml', '.yml']:
                    try:
                        with open(file_path, 'r') as f:
                            yaml.safe_load(f)
                        print(f"✓ Valid YAML: {update['file']}")
                    except Exception as e:
                        print(f"✗ Invalid YAML: {update['file']} - {e}")
                        return False
        
        return True

def main():
    parser = argparse.ArgumentParser(description='Update DPF versions in manifests')
    parser.add_argument('version', help='New DPF version (e.g., v25.4.0)')
    parser.add_argument('--components', nargs='+', 
                        help='Components to update (default: ovn-kubernetes flannel)')
    parser.add_argument('--dry-run', action='store_true',
                        help='Show what would be updated without making changes')
    parser.add_argument('--project-root', default='.',
                        help='Project root directory')
    parser.add_argument('--report', help='Output file for update report')
    
    args = parser.parse_args()
    
    # Find project root
    project_root = Path(args.project_root).resolve()
    
    # Validate project structure
    if not (project_root / 'manifests').exists():
        print(f"Error: manifests directory not found in {project_root}")
        sys.exit(1)
    
    updater = DPFVersionUpdater(project_root)
    
    # Perform updates
    results = updater.update_version_files(args.version, args.components)
    
    # Print results
    print("\nUpdate Summary:")
    print(f"- Successfully updated: {len(results['success'])} files")
    print(f"- Failed: {len(results['failed'])} files")
    print(f"- Skipped: {len(results['skipped'])} files")
    
    if results['failed']:
        print("\nFailed updates:")
        for file in results['failed']:
            print(f"  - {file}")
    
    # Validate updates
    if not args.dry_run:
        if not updater.validate_updates():
            print("\nValidation failed! Some files may be corrupted.")
            sys.exit(1)
    
    # Generate report
    report = updater.generate_update_report()
    
    if args.report:
        with open(args.report, 'w') as f:
            f.write(report)
        print(f"\nReport saved to: {args.report}")
    else:
        print("\n" + report)
    
    # Exit with appropriate code
    if results['failed']:
        sys.exit(1)
    else:
        sys.exit(0)

if __name__ == '__main__':
    main()