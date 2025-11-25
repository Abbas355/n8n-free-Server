#!/bin/bash
# test-all-clients.sh - Comprehensive test script for all client instances

BASE_DIR="/var/www/n8n-free-Server"
cd "$BASE_DIR" || exit 1

echo "=========================================="
echo "🧪 COMPREHENSIVE CLIENT TEST SUITE"
echo "=========================================="

TESTS_PASSED=0
TESTS_FAILED=0

test_result() {
    if [ $1 -eq 0 ]; then
        echo "✅ PASS: $2"
        ((TESTS_PASSED++))
    else
        echo "❌ FAIL: $2"
        ((TESTS_FAILED++))
    fi
}

# Test 1: Traefik
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 1: Traefik Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if docker ps | grep -q traefik; then
    test_result 0 "Traefik container is running"
else
    test_result 1 "Traefik container is NOT running"
fi

# Test 2: Network
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 2: Network Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if docker network inspect n8n-proxy &>/dev/null; then
    test_result 0 "n8n-proxy network exists"
else
    test_result 1 "n8n-proxy network is missing"
fi

# Test 3: Each client
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 3: Individual Client Health Checks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

CLIENT_COUNT=0
for CLIENT_DIR in clients/*/; do
    if [ -d "$CLIENT_DIR" ]; then
        CLIENT_ID=$(basename "$CLIENT_DIR")
        ((CLIENT_COUNT++))
        
        echo ""
        echo "📋 Testing Client: $CLIENT_ID"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        
        # Containers exist
        if docker ps --format "{{.Names}}" | grep -q "^n8n-${CLIENT_ID}$"; then
            test_result 0 "$CLIENT_ID: n8n container running"
        else
            test_result 1 "$CLIENT_ID: n8n container missing"
            continue
        fi
        
        docker ps --format "{{.Names}}" | grep -q "^postgres-${CLIENT_ID}$" && \
            test_result 0 "$CLIENT_ID: postgres container running" || \
            test_result 1 "$CLIENT_ID: postgres container missing"
        
        docker ps --format "{{.Names}}" | grep -q "^redis-${CLIENT_ID}$" && \
            test_result 0 "$CLIENT_ID: redis container running" || \
            test_result 1 "$CLIENT_ID: redis container missing"
        
        # Network connectivity
        docker network inspect n8n-proxy 2>/dev/null | grep -q "n8n-${CLIENT_ID}" && \
            test_result 0 "$CLIENT_ID: Connected to n8n-proxy" || \
            test_result 1 "$CLIENT_ID: NOT on n8n-proxy network"
        
        # Database health
        docker exec postgres-${CLIENT_ID} pg_isready -U n8nuser &>/dev/null && \
            test_result 0 "$CLIENT_ID: PostgreSQL healthy" || \
            test_result 1 "$CLIENT_ID: PostgreSQL unhealthy"
        
        # Redis health
        docker exec redis-${CLIENT_ID} redis-cli ping &>/dev/null | grep -q "PONG" && \
            test_result 0 "$CLIENT_ID: Redis healthy" || \
            test_result 1 "$CLIENT_ID: Redis unhealthy"
        
        # n8n health
        docker exec n8n-${CLIENT_ID} wget -q -O- http://localhost:5678/healthz 2>/dev/null | grep -q "ok" && \
            test_result 0 "$CLIENT_ID: n8n health check passed" || \
            test_result 1 "$CLIENT_ID: n8n health check failed"
        
        # Configuration check
        if [ -f "$CLIENT_DIR/docker-compose.yml" ]; then
            grep -q "N8N_PROXY_HOPS" "$CLIENT_DIR/docker-compose.yml" && \
                test_result 0 "$CLIENT_ID: N8N_PROXY_HOPS configured" || \
                test_result 1 "$CLIENT_ID: N8N_PROXY_HOPS missing"
        else
            test_result 1 "$CLIENT_ID: docker-compose.yml missing"
        fi
    fi
done

# Test 4: Resource conflicts
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 4: Resource Conflict Detection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DUPLICATES=$(docker ps --format "{{.Names}}" | grep -E "^(n8n|postgres|redis)-" | sort | uniq -d)
if [ -z "$DUPLICATES" ]; then
    test_result 0 "No duplicate container names"
else
    test_result 1 "Duplicate containers: $DUPLICATES"
fi

# Test 5: Disk space
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test 5: Disk Space Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

DISK_USAGE=$(df -h /var/www 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo "0")
if [ "$DISK_USAGE" -lt 80 ]; then
    test_result 0 "Disk usage is healthy (${DISK_USAGE}% used)"
else
    test_result 1 "Disk usage is high (${DISK_USAGE}% used) - consider cleanup"
fi

# Summary
echo ""
echo "=========================================="
echo "📊 TEST SUMMARY"
echo "=========================================="
echo "Total Clients Found: $CLIENT_COUNT"
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✅ ALL TESTS PASSED!"
    echo "System is healthy and ready for new client provisioning."
    exit 0
else
    echo "❌ SOME TESTS FAILED"
    echo "Please review the failed tests before provisioning new clients."
    exit 1
fi

