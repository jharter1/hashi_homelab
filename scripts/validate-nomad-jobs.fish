#!/usr/bin/env fish
# Validate Nomad job files
# Used by pre-commit hook

set FAILED 0

for job in $argv
    echo "Validating $job..."
    
    # Validate syntax
    nomad fmt -check $job
    if test $status -ne 0
        echo "ERROR: $job has formatting issues. Run: nomad fmt $job"
        set FAILED 1
    end
    
    # Validate job specification
    nomad job validate $job
    if test $status -ne 0
        echo "ERROR: $job failed validation"
        set FAILED 1
    end
    
    # Check for common anti-patterns
    if grep -q "restart_policy" $job
        echo "WARNING: $job uses deprecated 'restart_policy' - use 'restart' block instead"
    end
    
    if grep -q "data_dir" $job
        echo "WARNING: $job has data_dir in job spec (should be in agent config)"
    end
end

if test $FAILED -eq 1
    echo ""
    echo "❌ Validation failed! Fix errors above."
    exit 1
else
    echo ""
    echo "✅ All Nomad jobs validated successfully"
    exit 0
end
