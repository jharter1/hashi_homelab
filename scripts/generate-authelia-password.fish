#!/usr/bin/env fish
# Generate Argon2 password hash for Authelia users

echo "🔐 Generate Authelia Password Hash"
echo ""
echo "This will create an Argon2id hash for your password."
echo "Copy the output and use it in authelia.nomad.hcl users_database.yml"
echo ""

# Prompt for password (or use argument)
if test (count $argv) -eq 0
    echo -n "Enter password: "
    read -s password
    echo ""
    echo -n "Confirm password: "
    read -s password_confirm
    echo ""
    
    if test "$password" != "$password_confirm"
        echo "❌ Passwords don't match!"
        exit 1
    end
else
    set password $argv[1]
end

if test -z "$password"
    echo "❌ Password cannot be empty!"
    exit 1
end

echo "Generating hash..."
echo ""

# Check if Docker is available locally
if docker info >/dev/null 2>&1
    # Run locally
    docker run --rm authelia/authelia:latest \
        authelia crypto hash generate argon2 --password "$password"
else
    # Docker not running locally, use SSH to Nomad client
    echo "Docker not available locally. Running on Nomad client..."
    ssh ubuntu@10.0.0.60 "docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password '$password'"
    
    if test $status -ne 0
        echo ""
        echo "❌ Failed to generate hash"
        echo ""
        echo "Alternative: Run manually on any Nomad client:"
        echo "  ssh ubuntu@10.0.0.60"
        echo "  docker run --rm authelia/authelia:latest authelia crypto hash generate argon2 --password 'YOUR_PASSWORD'"
        exit 1
    end
end

echo ""
echo "✅ Copy the \$argon2id\$... hash above"
echo "   and use it in authelia.nomad.hcl users_database.yml template"
