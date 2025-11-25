#!/bin/bash
# test-new-client-creation.sh - Test creating a new client and verify it doesn't break existing ones

BASE_DIR="/var/www/n8n-free-Server"
cd "$BASE_DIR" || exit 1

# Test client name (will be cleaned up after)
TEST_CLIENT_NAME="test-client-$(date +%s)"
TEST_CLIENT_ID="test-client-$(date +%s)"

echo "=========================================="
echo "🧪 TEST: Creating New Client"
echo "=========================================="
echo "Test Client ID: $TEST_CLIENT_ID"
echo ""

# Step 1: Record existing clients before test
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Recording existing clients..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXISTING_CLIENTS=()
EXISTING_CONTAINERS=()

for CLIENT_DIR in clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        EXISTING_CLIENTS+=("$CLIENT_ID")
        EXISTING_CONTAINERS+=("n8n-$CLIENT_ID")
        EXISTING_CONTAINERS+=("postgres-$CLIENT_ID")
        EXISTING_CONTAINERS+=("redis-$CLIENT_ID")
    fi
done

echo "Found ${#EXISTING_CLIENTS[@]} existing clients:"
for client in "${EXISTING_CLIENTS[@]}"; do
    echo "  - $client"
done

# Step 2: Check existing clients are healthy BEFORE
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Verifying existing clients are healthy BEFORE new client creation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BEFORE_HEALTHY=0
BEFORE_UNHEALTHY=0

for CLIENT_ID in "${EXISTING_CLIENTS[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^n8n-${CLIENT_ID}$"; then
        if docker exec n8n-${CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
            echo "  ✅ $CLIENT_ID: Healthy"
            ((BEFORE_HEALTHY++))
        else
            echo "  ⚠️  $CLIENT_ID: Not healthy"
            ((BEFORE_UNHEALTHY++))
        fi
    else
        echo "  ⚠️  $CLIENT_ID: Container not running"
        ((BEFORE_UNHEALTHY++))
    fi
done

# Step 3: Create new test client
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Creating new test client..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "./provision-client.sh" ]; then
    bash ./provision-client.sh "$TEST_CLIENT_NAME"
    PROVISION_EXIT_CODE=$?
    
    if [ $PROVISION_EXIT_CODE -eq 0 ]; then
        echo "✅ Test client provisioned successfully"
    else
        echo "❌ Test client provisioning failed"
        exit 1
    fi
else
    echo "❌ provision-client.sh not found!"
    exit 1
fi

# Wait for initialization
echo ""
echo "⏳ Waiting 90 seconds for test client to fully initialize..."
sleep 90

# Step 4: Verify new client is healthy
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Verifying new test client is healthy..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NEW_CLIENT_HEALTHY=0

# Get actual client ID from directory
ACTUAL_CLIENT_ID=$(echo "$TEST_CLIENT_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | sed 's/[^a-z0-9-]//g')

if docker ps --format "{{.Names}}" | grep -q "^n8n-${ACTUAL_CLIENT_ID}$"; then
    if docker exec n8n-${ACTUAL_CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
        echo "✅ New client ($ACTUAL_CLIENT_ID) is healthy"
        NEW_CLIENT_HEALTHY=1
    else
        echo "❌ New client ($ACTUAL_CLIENT_ID) health check failed"
    fi
else
    echo "❌ New client container not found"
fi

# Step 5: Verify existing clients are STILL healthy AFTER
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 5: Verifying existing clients are STILL healthy AFTER new client creation..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

AFTER_HEALTHY=0
AFTER_UNHEALTHY=0
AFFECTED_CLIENTS=()

for CLIENT_ID in "${EXISTING_CLIENTS[@]}"; do
    if docker ps --format "{{.Names}}" | grep -q "^n8n-${CLIENT_ID}$"; then
        if docker exec n8n-${CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok"; then
            echo "  ✅ $CLIENT_ID: Still healthy"
            ((AFTER_HEALTHY++))
        else
            echo "  ❌ $CLIENT_ID: BROKEN!"
            AFFECTED_CLIENTS+=("$CLIENT_ID")
            ((AFTER_UNHEALTHY++))
        fi
    else
        echo "  ❌ $CLIENT_ID: Container stopped!"
        AFFECTED_CLIENTS+=("$CLIENT_ID")
        ((AFTER_UNHEALTHY++))
    fi
done

# Step 6: Check for container conflicts
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 6: Checking for resource conflicts..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check for duplicate container names
DUPLICATES=$(docker ps --format "{{.Names}}" | grep -E "^(n8n|postgres|redis)-" | sort | uniq -d)
if [ -z "$DUPLICATES" ]; then
    echo "✅ No container name conflicts"
else
    echo "❌ Container name conflicts detected: $DUPLICATES"
fi

# Check network conflicts
NETWORK_COUNT=$(docker network ls --format "{{.Name}}" | grep -E "${ACTUAL_CLIENT_ID}-internal" | wc -l)
if [ "$NETWORK_COUNT" -eq 1 ]; then
    echo "✅ No network conflicts"
else
    echo "⚠️  Unexpected network count for test client"
fi

# Step 7: Test Results Summary
echo ""
echo "=========================================="
echo "📊 TEST RESULTS SUMMARY"
echo "=========================================="
echo "Test Client Created: $ACTUAL_CLIENT_ID"
echo "New Client Status: $([ $NEW_CLIENT_HEALTHY -eq 1 ] && echo 'Healthy' || echo 'Unhealthy')"
echo ""
echo "Existing Clients BEFORE:"
echo "  Healthy: $BEFORE_HEALTHY"
echo "  Unhealthy: $BEFORE_UNHEALTHY"
echo ""
echo "Existing Clients AFTER:"
echo "  Healthy: $AFTER_HEALTHY"
echo "  Unhealthy: $AFTER_UNHEALTHY"
echo ""

if [ ${#AFFECTED_CLIENTS[@]} -gt 0 ]; then
    echo "❌ AFFECTED CLIENTS:"
    for client in "${AFFECTED_CLIENTS[@]}"; do
        echo "  - $client"
    done
    echo ""
    echo "❌ TEST FAILED: New client creation affected existing clients!"
    TEST_RESULT=1
else
    echo "✅ No existing clients were affected"
    TEST_RESULT=0
fi

# Step 8: Cleanup (optional - comment out if you want to keep test client)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 8: Cleaning up test client..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

read -p "Do you want to remove the test client? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    CLIENT_DIR="$BASE_DIR/clients/$ACTUAL_CLIENT_ID"
    if [ -d "$CLIENT_DIR" ]; then
        cd "$CLIENT_DIR"
        docker compose down 2>/dev/null
        cd "$BASE_DIR"
        rm -rf "$CLIENT_DIR"
        echo "✅ Test client removed"
    fi
else
    echo "⚠️  Test client kept at: clients/$ACTUAL_CLIENT_ID"
fi

echo ""
echo "=========================================="
if [ $TEST_RESULT -eq 0 ] && [ $NEW_CLIENT_HEALTHY -eq 1 ]; then
    echo "✅ ALL TESTS PASSED!"
    echo "New client provisioning works correctly and doesn't affect existing clients."
    exit 0
else
    echo "❌ TESTS FAILED!"
    echo "Please investigate the issues before provisioning production clients."
    exit 1
fi

