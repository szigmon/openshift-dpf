#!/usr/bin/env python3

"""
RDG Documentation Parser for DPF CI
Parses NVIDIA RDG documentation to extract configuration changes
"""

import os
import re
import sys
import json
import yaml
import argparse
import requests
from pathlib import Path
from typing import Dict, List, Tuple
from datetime import datetime
from bs4 import BeautifulSoup

class RDGParser:
    def __init__(self, cache_dir: str = None):
        self.cache_dir = Path(cache_dir) if cache_dir else Path.home() / '.cache' / 'dpf-ci'
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        self.rdg_base_url = "https://docs.nvidia.com/networking/display/public/sol"
        
    def fetch_rdg_doc(self, url: str = None, use_cache: bool = True) -> str:
        """Fetch RDG documentation from NVIDIA docs"""
        if url is None:
            url = f"{self.rdg_base_url}/rdg+for+dpf+with+ovn-kubernetes+and+hbn+services"
        
        # Check cache first
        cache_file = self.cache_dir / 'rdg-doc.html'
        if use_cache and cache_file.exists():
            # Check if cache is less than 24 hours old
            cache_age = datetime.now().timestamp() - cache_file.stat().st_mtime
            if cache_age < 86400:  # 24 hours
                print(f"Using cached RDG documentation (age: {cache_age/3600:.1f} hours)")
                with open(cache_file, 'r', encoding='utf-8') as f:
                    return f.read()
        
        print(f"Fetching RDG documentation from: {url}")
        try:
            response = requests.get(url, timeout=30)
            response.raise_for_status()
            
            # Cache the response
            with open(cache_file, 'w', encoding='utf-8') as f:
                f.write(response.text)
            
            return response.text
        except Exception as e:
            print(f"Error fetching RDG documentation: {e}")
            if cache_file.exists():
                print("Falling back to cached version")
                with open(cache_file, 'r', encoding='utf-8') as f:
                    return f.read()
            return ""
    
    def parse_configuration_sections(self, html_content: str) -> Dict:
        """Parse configuration sections from RDG HTML"""
        soup = BeautifulSoup(html_content, 'html.parser')
        
        configurations = {
            'dpf_version': None,
            'openshift_version': None,
            'helm_values': {},
            'environment_variables': {},
            'network_configuration': {},
            'service_configurations': {},
            'prerequisites': [],
            'known_issues': []
        }
        
        # Extract version information
        version_pattern = r'DPF\s+v?(\d+\.\d+\.\d+)'
        version_match = re.search(version_pattern, html_content)
        if version_match:
            configurations['dpf_version'] = f"v{version_match.group(1)}"
        
        # Extract OpenShift version
        os_pattern = r'OpenShift\s+(\d+\.\d+(?:\.\d+)?)'
        os_match = re.search(os_pattern, html_content)
        if os_match:
            configurations['openshift_version'] = os_match.group(1)
        
        # Parse code blocks for configurations
        code_blocks = soup.find_all(['code', 'pre'])
        for block in code_blocks:
            content = block.get_text().strip()
            
            # Check for YAML configurations
            if content.startswith('apiVersion:') or 'kind:' in content:
                self._parse_yaml_config(content, configurations)
            
            # Check for environment variables
            elif 'export ' in content or '=' in content:
                self._parse_env_vars(content, configurations)
            
            # Check for helm values
            elif 'helm ' in content or '--set' in content:
                self._parse_helm_values(content, configurations)
        
        # Extract network configuration
        self._extract_network_config(soup, configurations)
        
        # Extract prerequisites
        self._extract_prerequisites(soup, configurations)
        
        # Extract known issues
        self._extract_known_issues(soup, configurations)
        
        return configurations
    
    def _parse_yaml_config(self, content: str, configurations: Dict):
        """Parse YAML configuration blocks"""
        try:
            data = yaml.safe_load(content)
            if data and isinstance(data, dict):
                # Check for service configurations
                if 'kind' in data:
                    kind = data['kind']
                    if kind not in configurations['service_configurations']:
                        configurations['service_configurations'][kind] = []
                    configurations['service_configurations'][kind].append(data)
        except:
            # Not valid YAML, skip
            pass
    
    def _parse_env_vars(self, content: str, configurations: Dict):
        """Parse environment variable definitions"""
        lines = content.split('\n')
        for line in lines:
            # Match export VAR=value or VAR=value patterns
            match = re.match(r'(?:export\s+)?([A-Z_]+)=(.+)', line.strip())
            if match:
                var_name = match.group(1)
                var_value = match.group(2).strip('"\'')
                configurations['environment_variables'][var_name] = var_value
    
    def _parse_helm_values(self, content: str, configurations: Dict):
        """Parse helm command values"""
        # Extract --set flags
        set_pattern = r'--set\s+([^=]+)=([^\s]+)'
        for match in re.finditer(set_pattern, content):
            key = match.group(1)
            value = match.group(2)
            configurations['helm_values'][key] = value
        
        # Extract -f values files
        file_pattern = r'-f\s+(\S+\.yaml)'
        for match in re.finditer(file_pattern, content):
            configurations['helm_values']['_values_files'] = configurations['helm_values'].get('_values_files', [])
            configurations['helm_values']['_values_files'].append(match.group(1))
    
    def _extract_network_config(self, soup, configurations: Dict):
        """Extract network configuration details"""
        # Look for network-related configurations
        network_keywords = ['CIDR', 'subnet', 'VLAN', 'MTU', 'bridge', 'interface']
        
        for keyword in network_keywords:
            # Find paragraphs or list items containing network keywords
            elements = soup.find_all(text=re.compile(keyword, re.I))
            for element in elements:
                parent = element.parent
                if parent:
                    text = parent.get_text().strip()
                    # Extract IP ranges
                    ip_pattern = r'\b(?:\d{1,3}\.){3}\d{1,3}(?:/\d{1,2})?\b'
                    ips = re.findall(ip_pattern, text)
                    if ips:
                        configurations['network_configuration'][keyword] = ips
    
    def _extract_prerequisites(self, soup, configurations: Dict):
        """Extract prerequisites section"""
        # Look for prerequisites heading
        prereq_headings = soup.find_all(['h2', 'h3'], text=re.compile('prerequisite', re.I))
        
        for heading in prereq_headings:
            # Get the next sibling elements until next heading
            current = heading.find_next_sibling()
            while current and current.name not in ['h1', 'h2', 'h3']:
                if current.name == 'ul':
                    for li in current.find_all('li'):
                        prereq = li.get_text().strip()
                        if prereq:
                            configurations['prerequisites'].append(prereq)
                elif current.name == 'p':
                    text = current.get_text().strip()
                    if text:
                        configurations['prerequisites'].append(text)
                current = current.find_next_sibling()
    
    def _extract_known_issues(self, soup, configurations: Dict):
        """Extract known issues section"""
        # Look for known issues heading
        issue_headings = soup.find_all(['h2', 'h3'], text=re.compile('known issue|limitation', re.I))
        
        for heading in issue_headings:
            current = heading.find_next_sibling()
            while current and current.name not in ['h1', 'h2', 'h3']:
                if current.name == 'ul':
                    for li in current.find_all('li'):
                        issue = li.get_text().strip()
                        if issue:
                            configurations['known_issues'].append(issue)
                elif current.name == 'p':
                    text = current.get_text().strip()
                    if text and len(text) > 20:  # Filter out very short texts
                        configurations['known_issues'].append(text)
                current = current.find_next_sibling()
    
    def compare_configurations(self, old_config: Dict, new_config: Dict) -> Dict:
        """Compare two configuration dictionaries"""
        changes = {
            'version_changes': {},
            'env_var_changes': {
                'added': {},
                'removed': {},
                'modified': {}
            },
            'helm_value_changes': {
                'added': {},
                'removed': {},
                'modified': {}
            },
            'network_changes': {},
            'new_prerequisites': [],
            'new_issues': []
        }
        
        # Compare versions
        if old_config['dpf_version'] != new_config['dpf_version']:
            changes['version_changes']['dpf'] = {
                'old': old_config['dpf_version'],
                'new': new_config['dpf_version']
            }
        
        if old_config['openshift_version'] != new_config['openshift_version']:
            changes['version_changes']['openshift'] = {
                'old': old_config['openshift_version'],
                'new': new_config['openshift_version']
            }
        
        # Compare environment variables
        self._compare_dicts(
            old_config['environment_variables'],
            new_config['environment_variables'],
            changes['env_var_changes']
        )
        
        # Compare helm values
        self._compare_dicts(
            old_config['helm_values'],
            new_config['helm_values'],
            changes['helm_value_changes']
        )
        
        # Compare prerequisites
        new_prereqs = set(new_config['prerequisites']) - set(old_config['prerequisites'])
        changes['new_prerequisites'] = list(new_prereqs)
        
        # Compare known issues
        new_issues = set(new_config['known_issues']) - set(old_config['known_issues'])
        changes['new_issues'] = list(new_issues)
        
        return changes
    
    def _compare_dicts(self, old_dict: Dict, new_dict: Dict, changes: Dict):
        """Compare two dictionaries and populate changes"""
        all_keys = set(old_dict.keys()) | set(new_dict.keys())
        
        for key in all_keys:
            if key not in old_dict:
                changes['added'][key] = new_dict[key]
            elif key not in new_dict:
                changes['removed'][key] = old_dict[key]
            elif old_dict[key] != new_dict[key]:
                changes['modified'][key] = {
                    'old': old_dict[key],
                    'new': new_dict[key]
                }
    
    def generate_report(self, configurations: Dict, output_path: str = None) -> str:
        """Generate a report from parsed configurations"""
        report = []
        
        report.append("# RDG Documentation Analysis")
        report.append(f"\n**Date**: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        
        if configurations['dpf_version']:
            report.append(f"**DPF Version**: {configurations['dpf_version']}")
        
        if configurations['openshift_version']:
            report.append(f"**OpenShift Version**: {configurations['openshift_version']}")
        
        # Environment Variables
        if configurations['environment_variables']:
            report.append("\n## Environment Variables")
            for var, value in sorted(configurations['environment_variables'].items()):
                report.append(f"- `{var}={value}`")
        
        # Helm Values
        if configurations['helm_values']:
            report.append("\n## Helm Values")
            for key, value in sorted(configurations['helm_values'].items()):
                if key != '_values_files':
                    report.append(f"- `{key}`: {value}")
            
            if '_values_files' in configurations['helm_values']:
                report.append("\n### Values Files")
                for file in configurations['helm_values']['_values_files']:
                    report.append(f"- {file}")
        
        # Network Configuration
        if configurations['network_configuration']:
            report.append("\n## Network Configuration")
            for key, values in configurations['network_configuration'].items():
                report.append(f"- **{key}**: {', '.join(values)}")
        
        # Prerequisites
        if configurations['prerequisites']:
            report.append("\n## Prerequisites")
            for prereq in configurations['prerequisites']:
                report.append(f"- {prereq}")
        
        # Known Issues
        if configurations['known_issues']:
            report.append("\n## Known Issues")
            for issue in configurations['known_issues']:
                report.append(f"- {issue}")
        
        report_text = '\n'.join(report)
        
        if output_path:
            with open(output_path, 'w') as f:
                f.write(report_text)
            print(f"Report saved to: {output_path}")
        
        return report_text

def main():
    parser = argparse.ArgumentParser(description='Parse NVIDIA RDG documentation')
    parser.add_argument('--url', help='RDG documentation URL')
    parser.add_argument('--cache-dir', help='Cache directory')
    parser.add_argument('--no-cache', action='store_true', help='Skip cache')
    parser.add_argument('--output', help='Output file for report')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    parser.add_argument('--compare', help='Compare with saved configuration file')
    
    args = parser.parse_args()
    
    rdg_parser = RDGParser(cache_dir=args.cache_dir)
    
    # Fetch and parse documentation
    html_content = rdg_parser.fetch_rdg_doc(url=args.url, use_cache=not args.no_cache)
    
    if not html_content:
        print("Failed to fetch RDG documentation")
        sys.exit(1)
    
    configurations = rdg_parser.parse_configuration_sections(html_content)
    
    # Compare with previous version if specified
    if args.compare:
        with open(args.compare, 'r') as f:
            old_config = json.load(f)
        
        changes = rdg_parser.compare_configurations(old_config, configurations)
        
        if args.json:
            print(json.dumps(changes, indent=2))
        else:
            print("\nConfiguration Changes:")
            print(json.dumps(changes, indent=2))
    else:
        # Output results
        if args.json:
            print(json.dumps(configurations, indent=2))
        else:
            report = rdg_parser.generate_report(configurations, args.output)
            if not args.output:
                print(report)
    
    # Save configuration for future comparisons
    config_file = Path(args.cache_dir or '.') / f"rdg-config-{datetime.now().strftime('%Y%m%d')}.json"
    with open(config_file, 'w') as f:
        json.dump(configurations, f, indent=2)
    print(f"\nConfiguration saved to: {config_file}")

if __name__ == '__main__':
    main()