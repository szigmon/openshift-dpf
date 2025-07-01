#!/usr/bin/env python3

"""
Version Comparison Script for DPF CI
Compares manifests and configurations between DPF versions
"""

import os
import sys
import yaml
import json
import argparse
import tempfile
import subprocess
from typing import Dict, List, Set, Tuple
from pathlib import Path
from dataclasses import dataclass
from datetime import datetime

@dataclass
class VersionChange:
    """Represents a change between versions"""
    file_path: str
    change_type: str  # added, removed, modified
    old_value: str = ""
    new_value: str = ""
    description: str = ""

class DPFVersionComparator:
    def __init__(self, config_path: str):
        self.config_path = Path(config_path)
        self.config = self._load_config()
        self.changes: List[VersionChange] = []
        
    def _load_config(self) -> dict:
        """Load version configuration from YAML"""
        with open(self.config_path, 'r') as f:
            return yaml.safe_load(f)
    
    def _clone_version(self, version: str, target_dir: str) -> bool:
        """Clone specific version of DOCA platform"""
        repo_url = self.config['dpf_versions']['repository']
        branch_pattern = self.config['dpf_versions']['release_branch_pattern']
        branch_name = branch_pattern.replace('{version}', version)
        
        print(f"Cloning {version} to {target_dir}...")
        
        cmd = [
            'git', 'clone', 
            '--depth', '1',
            '--branch', branch_name,
            repo_url,
            target_dir
        ]
        
        try:
            subprocess.run(cmd, check=True, capture_output=True, text=True)
            return True
        except subprocess.CalledProcessError as e:
            print(f"Failed to clone {version}: {e}")
            return False
    
    def _extract_api_versions(self, manifest_dir: str) -> Dict[str, str]:
        """Extract API versions from manifests"""
        api_versions = {}
        
        for yaml_file in Path(manifest_dir).rglob('*.yaml'):
            try:
                with open(yaml_file, 'r') as f:
                    docs = yaml.safe_load_all(f)
                    for doc in docs:
                        if doc and 'apiVersion' in doc and 'kind' in doc:
                            kind = doc['kind']
                            api_version = doc['apiVersion']
                            if kind not in api_versions:
                                api_versions[kind] = set()
                            api_versions[kind].add(api_version)
            except Exception as e:
                print(f"Error parsing {yaml_file}: {e}")
        
        # Convert sets to lists for JSON serialization
        return {k: list(v) for k, v in api_versions.items()}
    
    def _extract_helm_versions(self, manifest_dir: str) -> Dict[str, str]:
        """Extract Helm chart versions from manifests"""
        helm_versions = {}
        
        # Look for DPU service templates
        service_files = [
            'ovn-template.yaml',
            'flannel-template.yaml',
            'hbn-template.yaml',
            'blueman-template.yaml',
            'dts-template.yaml'
        ]
        
        for service_file in service_files:
            file_path = Path(manifest_dir) / 'manifests' / 'post-installation' / service_file
            if not file_path.exists():
                # Try alternative paths
                file_path = Path(manifest_dir) / 'examples' / 'dpf' / service_file
            
            if file_path.exists():
                try:
                    with open(file_path, 'r') as f:
                        data = yaml.safe_load(f)
                        
                    if data and 'spec' in data and 'helmChart' in data['spec']:
                        helm_spec = data['spec']['helmChart']
                        if 'source' in helm_spec:
                            chart = helm_spec['source'].get('chart', '')
                            version = helm_spec['source'].get('version', '')
                            if chart and version:
                                helm_versions[chart] = version
                except Exception as e:
                    print(f"Error parsing {file_path}: {e}")
        
        return helm_versions
    
    def _compare_files(self, file1: Path, file2: Path) -> List[str]:
        """Compare two files and return differences"""
        differences = []
        
        # If one file exists and the other doesn't
        if file1.exists() and not file2.exists():
            return [f"File removed: {file1.name}"]
        elif not file1.exists() and file2.exists():
            return [f"File added: {file2.name}"]
        elif not file1.exists() and not file2.exists():
            return []
        
        # Both files exist, compare content
        try:
            with open(file1, 'r') as f1, open(file2, 'r') as f2:
                content1 = f1.read()
                content2 = f2.read()
                
            if content1 != content2:
                # Try to parse as YAML for better comparison
                try:
                    yaml1 = yaml.safe_load(content1)
                    yaml2 = yaml.safe_load(content2)
                    
                    # Compare specific fields
                    if isinstance(yaml1, dict) and isinstance(yaml2, dict):
                        for key in set(yaml1.keys()) | set(yaml2.keys()):
                            if key not in yaml1:
                                differences.append(f"Field added: {key}")
                            elif key not in yaml2:
                                differences.append(f"Field removed: {key}")
                            elif yaml1[key] != yaml2[key]:
                                differences.append(f"Field modified: {key}")
                except:
                    differences.append("Content modified")
        except Exception as e:
            differences.append(f"Error comparing files: {e}")
        
        return differences
    
    def compare_versions(self, old_version: str, new_version: str) -> Dict:
        """Compare two DPF versions"""
        print(f"\nComparing DPF versions: {old_version} -> {new_version}")
        
        with tempfile.TemporaryDirectory() as temp_dir:
            old_dir = os.path.join(temp_dir, 'old')
            new_dir = os.path.join(temp_dir, 'new')
            
            # Clone both versions
            if not self._clone_version(old_version, old_dir):
                return {"error": f"Failed to clone {old_version}"}
            
            if not self._clone_version(new_version, new_dir):
                return {"error": f"Failed to clone {new_version}"}
            
            # Extract information from both versions
            old_api_versions = self._extract_api_versions(old_dir)
            new_api_versions = self._extract_api_versions(new_dir)
            
            old_helm_versions = self._extract_helm_versions(old_dir)
            new_helm_versions = self._extract_helm_versions(new_dir)
            
            # Compare API versions
            api_changes = self._compare_api_versions(old_api_versions, new_api_versions)
            
            # Compare Helm versions
            helm_changes = self._compare_helm_versions(old_helm_versions, new_helm_versions)
            
            # Compare specific files
            file_changes = self._compare_specific_files(old_dir, new_dir)
            
            return {
                "old_version": old_version,
                "new_version": new_version,
                "comparison_date": datetime.now().isoformat(),
                "api_changes": api_changes,
                "helm_changes": helm_changes,
                "file_changes": file_changes,
                "summary": self._generate_summary(api_changes, helm_changes, file_changes)
            }
    
    def _compare_api_versions(self, old_apis: Dict, new_apis: Dict) -> Dict:
        """Compare API versions between releases"""
        changes = {
            "added": {},
            "removed": {},
            "modified": {}
        }
        
        all_kinds = set(old_apis.keys()) | set(new_apis.keys())
        
        for kind in all_kinds:
            if kind not in old_apis:
                changes["added"][kind] = new_apis[kind]
            elif kind not in new_apis:
                changes["removed"][kind] = old_apis[kind]
            elif old_apis[kind] != new_apis[kind]:
                changes["modified"][kind] = {
                    "old": old_apis[kind],
                    "new": new_apis[kind]
                }
        
        return changes
    
    def _compare_helm_versions(self, old_helm: Dict, new_helm: Dict) -> Dict:
        """Compare Helm chart versions"""
        changes = {
            "upgraded": {},
            "downgraded": {},
            "added": {},
            "removed": {}
        }
        
        all_charts = set(old_helm.keys()) | set(new_helm.keys())
        
        for chart in all_charts:
            if chart not in old_helm:
                changes["added"][chart] = new_helm[chart]
            elif chart not in new_helm:
                changes["removed"][chart] = old_helm[chart]
            elif old_helm[chart] != new_helm[chart]:
                # Determine if upgraded or downgraded
                try:
                    from packaging import version
                    if version.parse(new_helm[chart]) > version.parse(old_helm[chart]):
                        changes["upgraded"][chart] = {
                            "from": old_helm[chart],
                            "to": new_helm[chart]
                        }
                    else:
                        changes["downgraded"][chart] = {
                            "from": old_helm[chart],
                            "to": new_helm[chart]
                        }
                except:
                    # If version parsing fails, just mark as upgraded
                    changes["upgraded"][chart] = {
                        "from": old_helm[chart],
                        "to": new_helm[chart]
                    }
        
        return changes
    
    def _compare_specific_files(self, old_dir: str, new_dir: str) -> List[Dict]:
        """Compare specific files between versions"""
        file_changes = []
        
        # Get list of version-sensitive files from config
        sensitive_files = self.config.get('version_sensitive_files', [])
        
        for file_path in sensitive_files:
            old_file = Path(old_dir) / file_path
            new_file = Path(new_dir) / file_path
            
            differences = self._compare_files(old_file, new_file)
            
            if differences:
                file_changes.append({
                    "file": file_path,
                    "changes": differences
                })
        
        return file_changes
    
    def _generate_summary(self, api_changes: Dict, helm_changes: Dict, file_changes: List) -> Dict:
        """Generate a summary of changes"""
        summary = {
            "total_api_changes": sum(len(v) for v in api_changes.values()),
            "total_helm_changes": sum(len(v) for v in helm_changes.values()),
            "total_file_changes": len(file_changes),
            "breaking_changes": [],
            "recommendations": []
        }
        
        # Check for breaking changes
        if api_changes["removed"]:
            summary["breaking_changes"].append("API resources removed")
            summary["recommendations"].append("Review removed APIs and update manifests")
        
        if api_changes["modified"]:
            summary["breaking_changes"].append("API versions changed")
            summary["recommendations"].append("Update API versions in manifests")
        
        if helm_changes["downgraded"]:
            summary["recommendations"].append("Helm charts downgraded - verify compatibility")
        
        # Add recommendations based on changes
        if helm_changes["upgraded"]:
            summary["recommendations"].append("Test with new Helm chart versions")
        
        if file_changes:
            summary["recommendations"].append("Review file changes and update automation scripts")
        
        return summary
    
    def generate_report(self, comparison_result: Dict, output_path: str = None) -> str:
        """Generate a markdown report from comparison results"""
        report = []
        
        report.append(f"# DPF Version Comparison Report")
        report.append(f"\n**Date**: {comparison_result['comparison_date']}")
        report.append(f"**Versions**: {comparison_result['old_version']} → {comparison_result['new_version']}")
        
        # Summary
        summary = comparison_result['summary']
        report.append(f"\n## Summary")
        report.append(f"- Total API changes: {summary['total_api_changes']}")
        report.append(f"- Total Helm changes: {summary['total_helm_changes']}")
        report.append(f"- Total file changes: {summary['total_file_changes']}")
        
        if summary['breaking_changes']:
            report.append(f"\n### ⚠️ Breaking Changes")
            for change in summary['breaking_changes']:
                report.append(f"- {change}")
        
        if summary['recommendations']:
            report.append(f"\n### 📋 Recommendations")
            for rec in summary['recommendations']:
                report.append(f"- {rec}")
        
        # API Changes
        api_changes = comparison_result['api_changes']
        if any(api_changes.values()):
            report.append(f"\n## API Changes")
            
            if api_changes['added']:
                report.append(f"\n### Added APIs")
                for kind, versions in api_changes['added'].items():
                    report.append(f"- **{kind}**: {', '.join(versions)}")
            
            if api_changes['removed']:
                report.append(f"\n### Removed APIs")
                for kind, versions in api_changes['removed'].items():
                    report.append(f"- **{kind}**: {', '.join(versions)}")
            
            if api_changes['modified']:
                report.append(f"\n### Modified APIs")
                for kind, change in api_changes['modified'].items():
                    report.append(f"- **{kind}**: {', '.join(change['old'])} → {', '.join(change['new'])}")
        
        # Helm Changes
        helm_changes = comparison_result['helm_changes']
        if any(helm_changes.values()):
            report.append(f"\n## Helm Chart Changes")
            
            if helm_changes['upgraded']:
                report.append(f"\n### Upgraded Charts")
                for chart, versions in helm_changes['upgraded'].items():
                    report.append(f"- **{chart}**: {versions['from']} → {versions['to']}")
            
            if helm_changes['added']:
                report.append(f"\n### Added Charts")
                for chart, version in helm_changes['added'].items():
                    report.append(f"- **{chart}**: {version}")
        
        # File Changes
        file_changes = comparison_result.get('file_changes', [])
        if file_changes:
            report.append(f"\n## File Changes")
            for file_change in file_changes:
                report.append(f"\n### {file_change['file']}")
                for change in file_change['changes']:
                    report.append(f"- {change}")
        
        report_text = '\n'.join(report)
        
        if output_path:
            with open(output_path, 'w') as f:
                f.write(report_text)
            print(f"Report saved to: {output_path}")
        
        return report_text

def main():
    parser = argparse.ArgumentParser(description='Compare DPF versions')
    parser.add_argument('--config', default='ci/config/versions.yaml',
                        help='Path to versions config file')
    parser.add_argument('--old-version', required=True,
                        help='Old version to compare (e.g., v25.1.1)')
    parser.add_argument('--new-version', required=True,
                        help='New version to compare (e.g., v25.4.0)')
    parser.add_argument('--output', help='Output file for comparison report')
    parser.add_argument('--json', action='store_true',
                        help='Output results as JSON')
    
    args = parser.parse_args()
    
    # Find config file
    if not os.path.isabs(args.config):
        # Try to find config relative to script location
        script_dir = Path(__file__).parent
        config_path = script_dir.parent / 'config' / 'versions.yaml'
        if not config_path.exists():
            # Try from project root
            config_path = Path.cwd() / args.config
    else:
        config_path = Path(args.config)
    
    if not config_path.exists():
        print(f"Error: Config file not found: {config_path}")
        sys.exit(1)
    
    comparator = DPFVersionComparator(config_path)
    result = comparator.compare_versions(args.old_version, args.new_version)
    
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        report = comparator.generate_report(result, args.output)
        if not args.output:
            print(report)

if __name__ == '__main__':
    main()