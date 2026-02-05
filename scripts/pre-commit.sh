#!/usr/bin/env bash
# Pre-commit hook to prevent committing sensitive information
# Install: cp scripts/pre-commit.sh .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

FILES=$(git diff --cached --name-only --diff-filter=ACM)

# Check for sensitive file patterns
echo "🔍 Checking for sensitive files..."
if echo "$FILES" | grep -qE '(\.tfstate$|^\.credentials$|vault.*credentials|SENSITIVE_INFO_ACTUAL)'; then
    echo -e "${RED}❌ Blocked: Attempting to commit sensitive files!${NC}"
    echo "Files:"
    echo "$FILES" | grep -E '(\.tfstate$|^\.credentials$|vault.*credentials|SENSITIVE_INFO_ACTUAL)'
    echo ""
    echo "These files should be in .gitignore"
    exit 1
fi

# Get files that aren't documentation
NON_DOC_FILES=$(echo "$FILES" | grep -vE '(SENSITIVE_INFO\.md|\.example|README\.md|SECURITY_|docs/)')

# Check for Vault tokens in non-documentation files
if [ ! -z "$NON_DOC_FILES" ]; then
    echo "🔍 Checking for Vault tokens in code files..."
    if echo "$NON_DOC_FILES" | while read -r file; do
        git diff --cached -- "$file" | grep -qE 'hvs\.[A-Za-z0-9]{24,}' && echo "$file"
    done | grep -q .; then
        echo -e "${RED}❌ Blocked: Vault token detected in code files!${NC}"
        echo ""
        echo "Use .credentials file instead of hardcoding tokens"
        exit 1
    fi
fi

echo "✅ Pre-commit checks passed"
exit 0
