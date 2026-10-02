import os
import sys
import glob
import requests
from datetime import datetime
from anthropic import Anthropic

# Initialize client
client = Anthropic(api_key=os.environ.get("ANTHROPIC_API_KEY"))

EXCLUDE_PATHS = ["Pods", "Carthage", ".build", "DerivedData", "Tests", "UITests"]

def collect_source_files(root_dir="."):
    source_code = ""
    for file_path in glob.glob(f"{root_dir}/**/*.swift", recursive=True):
        if any(excluded in file_path for excluded in EXCLUDE_PATHS):
            continue
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
                source_code += f"\n--- FILE: {file_path} ---\n{content}\n"
        except Exception as e:
            print(f"Error reading {file_path}: {e}")
    return source_code

def create_private_advisory(report_text):
    github_token = os.environ.get("GITHUB_TOKEN")
    repo = os.environ.get("GITHUB_REPOSITORY") # Formats automatically as owner/repo
    
    url = f"https://api.github.com/repos/{repo}/security-advisories"
    headers = {
        "Authorization": f"Bearer {github_token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28"
    }

    today_str = datetime.now().strftime("%Y-%m-%d")
    payload = {
        "summary": f"Daily iOS Security & Privacy Audit Report - {today_str}",
        "description": report_text,
        "severity": "medium",
        "vulnerabilities": [{"package": {"ecosystem": "swift", "name": "Autheris"}}]
    }

    response = requests.post(url, headers=headers, json=payload)
    if response.status_code == 201:
        print("Successfully created private GitHub Security Advisory.")
    else:
        print(f"Failed to create advisory: {response.status_code} - {response.text}")
        sys.exit(1)

def main():
    print("Collecting Swift source files...")
    codebase = collect_source_files()

    if not codebase:
        print("No Swift source files found.")
        return

    system_prompt = """
    You are an expert iOS Security & Privacy Code Auditor. Analyze the provided Swift code for security vulnerabilities, privacy issues, and insecure coding patterns according to OWASP MASVS and Apple Privacy Guidelines.
    
    Structure every finding using clear Markdown:
    ### [Title]
    - **Severity**: [Critical/High/Medium/Low]
    - **Category**: [Data Protection / Network / Privacy / Auth]
    - **Location**: `File path / Line or Symbol`
    - **Risk**: Explanation of the vulnerability.
    - **Remediation**: Corrected Swift code snippet.
    
    If no issues are found, explicitly output "No security or privacy weaknesses identified."
    """

    print("Analyzing codebase with Claude Opus 5.5...")
    response = client.messages.create(
        model="claude-opus-5-5",
        max_tokens=4000,
        system=system_prompt,
        messages=[
            {
                "role": "user",
                "content": f"Please perform a security and privacy audit on the following iOS source code:\n\n{codebase}"
            }
        ]
    )

    # Safely iterate through all content blocks to ignore ThinkingBlocks and gather TextBlocks
    report_text = "".join(
        block.text for block in response.content if getattr(block, "type", None) == "text"
    )

    if not report_text.strip() or "No security or privacy weaknesses identified." in report_text:
        print("No security or privacy weaknesses identified. Skipping advisory.")
        return

    print("Publishing findings to GitHub Security Advisories...")
    create_private_advisory(report_text)

if __name__ == "__main__":
    main()
