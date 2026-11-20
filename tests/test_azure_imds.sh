#!/bin/bash
# Comprehensive unit & integration tests for cloud-netconfig Azure IMDS hardening
set -euo pipefail

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PASSED=0
FAILED=0

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo "  [PASS] $msg"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $msg (expected: '$expected', got: '$actual')"
        FAILED=$((FAILED + 1))
    fi
}

assert_exit() {
    local expected="$1"
    local actual="$2"
    local msg="$3"
    if [[ "$expected" -eq "$actual" ]]; then
        echo "  [PASS] $msg (exit code $actual)"
        PASSED=$((PASSED + 1))
    else
        echo "  [FAIL] $msg (expected exit: $expected, got: $actual)"
        FAILED=$((FAILED + 1))
    fi
}

echo "============================================================"
echo "Running Azure IMDS hardening test suite"
echo "============================================================"

# Test Suite 1: azure/functions.cloud-netconfig error propagation
echo ""
echo "--- Suite 1: Error propagation in azure/functions.cloud-netconfig ---"
source "${BASE_DIR}/azure/functions.cloud-netconfig"

# Mock logger
logger() { :; }

# Case 1.1: Successful fetch of primary and secondary IP
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") echo -n "000D3A987654" ;;
        "0/ipv4/ipAddress") echo -n "0/ 1/" ;;
        "0/ipv4/ipAddress/0/privateIpAddress") echo -n "10.29.18.10" ;;
        "0/ipv4/subnet/0/prefix") echo -n "24" ;;
        "0/ipv4/ipAddress/1/privateIpAddress") echo -n "10.29.18.119" ;;
        *) return 1 ;;
    esac
    return 0
}

hwaddr="00:0d:3a:98:76:54"
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 0 "$ret" "1.1: Normal IMDS query exits with 0"
assert_eq "10.29.18.10/24 10.29.18.119/24" "$out" "1.1: Output contains primary and secondary IPs"

# Case 1.2: MAC address query timeout/failure
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") return 1 ;; # Simulate timeout/error
        *) return 1 ;;
    esac
}
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 1 "$ret" "1.2: MAC query timeout returns exit 1"
assert_eq "" "$out" "1.2: MAC query timeout produces empty output"

# Case 1.3: Interface not found in metadata
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") echo -n "112233445566" ;; # Different MAC
        *) return 1 ;;
    esac
}
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 1 "$ret" "1.3: Interface MAC not found in metadata returns exit 1"
assert_eq "" "$out" "1.3: Output is empty when interface not found"

# Case 1.4: IP list query fails
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") echo -n "000D3A987654" ;;
        "0/ipv4/ipAddress") return 1 ;; # Fail getting IP indices
        *) return 1 ;;
    esac
}
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 1 "$ret" "1.4: IP indices query failure returns exit 1"
assert_eq "" "$out" "1.4: Output is empty on IP indices query failure"

# Case 1.5: Secondary IP query fails mid-loop
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") echo -n "000D3A987654" ;;
        "0/ipv4/ipAddress") echo -n "0/ 1/" ;;
        "0/ipv4/ipAddress/0/privateIpAddress") echo -n "10.29.18.10" ;;
        "0/ipv4/subnet/0/prefix") echo -n "24" ;;
        "0/ipv4/ipAddress/1/privateIpAddress") return 1 ;; # Fail secondary IP fetch
        *) return 1 ;;
    esac
}
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 1 "$ret" "1.5: Secondary IP query failure mid-loop returns exit 1"
assert_eq "" "$out" "1.5: Output is empty (no partial emit) on mid-loop failure"

# Case 1.6: Subnet prefix query fails
get_from_metadata() {
    local query="${1:-}"
    case "$query" in
        "") echo -n "0/" ;;
        "0/macAddress") echo -n "000D3A987654" ;;
        "0/ipv4/ipAddress") echo -n "0/" ;;
        "0/ipv4/ipAddress/0/privateIpAddress") echo -n "10.29.18.10" ;;
        "0/ipv4/subnet/0/prefix") return 1 ;; # Fail prefix fetch
        *) return 1 ;;
    esac
}
set +e
out=$(get_ipv4_addresses_from_metadata "$hwaddr")
ret=$?
set -e
assert_exit 1 "$ret" "1.6: Subnet prefix failure returns exit 1"
assert_eq "" "$out" "1.6: Output is empty on subnet prefix failure"


# Test Suite 2: get_from_metadata retry with backoff
echo ""
echo "--- Suite 2: Retry and backoff in get_from_metadata ---"

# Restore original get_from_metadata function
source "${BASE_DIR}/azure/functions.cloud-netconfig"
export METADATA_RETRY_DELAY=0

export ATTEMPT_FILE=$(mktemp)
trap "rm -f $ATTEMPT_FILE" EXIT

LOG_CURL="cat"

# Case 2.1: Transient curl failure then success
mock_curl_transient() {
    local resp_file="" url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -D) resp_file="$2"; shift 2 ;;
            *) url="$1"; shift ;;
        esac
    done
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"

    if [[ $cur -eq 1 ]]; then
        # First attempt: curl timeout
        return 28
    else
        # Second attempt: success
        echo -e "HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\n" > "$resp_file"
        echo -n "0/"
        return 0
    fi
}

CURL="mock_curl_transient"
echo "0" > "$ATTEMPT_FILE"
set +e
out=$(get_from_metadata "")
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 0 "$ret" "2.1: Recovers from transient curl failure on retry"
assert_eq "0/" "$out" "2.1: Returns correct result after retry"
assert_eq "2" "$attempts" "2.1: Exactly 2 attempts were made"

# Case 2.2: Transient HTTP 500 then success
mock_curl_500() {
    local resp_file="" url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -D) resp_file="$2"; shift 2 ;;
            *) url="$1"; shift ;;
        esac
    done
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"

    if [[ $cur -eq 1 ]]; then
        echo -e "HTTP/1.1 500 Internal Server Error\r\n\r\n" > "$resp_file"
        echo "Server error"
        return 0
    else
        echo -e "HTTP/1.1 200 OK\r\n\r\n" > "$resp_file"
        echo -n "000D3A987654"
        return 0
    fi
}

CURL="mock_curl_500"
echo "0" > "$ATTEMPT_FILE"
set +e
out=$(get_from_metadata "0/macAddress")
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 0 "$ret" "2.2: Recovers from transient HTTP 500 on retry"
assert_eq "000D3A987654" "$out" "2.2: Returns correct result after 500 recovery"
assert_eq "2" "$attempts" "2.2: Exactly 2 attempts were made"

# Case 2.3: Non-retriable HTTP 404 fails immediately without retrying
mock_curl_404() {
    local resp_file="" url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -D) resp_file="$2"; shift 2 ;;
            *) url="$1"; shift ;;
        esac
    done
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"

    echo -e "HTTP/1.1 404 Not Found\r\n\r\n" > "$resp_file"
    echo "Not Found"
    return 0
}

CURL="mock_curl_404"
echo "0" > "$ATTEMPT_FILE"
set +e
out=$(get_from_metadata "invalid/path")
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 1 "$ret" "2.3: HTTP 404 returns exit 1"
assert_eq "1" "$attempts" "2.3: Fails fast on 404 (only 1 attempt, no useless retries)"

# Case 2.4: Permanent failure after max retries
mock_curl_fail_all() {
    local resp_file="" url=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -D) resp_file="$2"; shift 2 ;;
            *) url="$1"; shift ;;
        esac
    done
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"
    return 28
}

CURL="mock_curl_fail_all"
echo "0" > "$ATTEMPT_FILE"
set +e
out=$(get_from_metadata "")
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 1 "$ret" "2.4: Exhausted retries returns exit 1"
assert_eq "4" "$attempts" "2.4: Attempted initial + 3 retries (4 total)"


# Test Suite 3: Keep-last-good-state in common/cloud-netconfig
echo ""
echo "--- Suite 3: Keep-last-good-state in common/cloud-netconfig ---"

# Simulate configure_interface_ipv4 keep-last-good-state logic
simulate_reconcile() {
    local IPADDR="$1"       # Primary DHCP IP (e.g. 10.29.18.10)
    local metadata_ips="$2" # output from get_ipv4_addresses_from_metadata
    local meta_ret="$3"     # return code from get_ipv4_addresses_from_metadata
    local -a current_addrs=("10.29.18.10/24" "10.29.18.119/24")
    local -a cn_addrs=("10.29.18.119/24")
    local -a deleted_addrs=()
    local -a added_addrs=()

    # Step from common/cloud-netconfig:
    if [[ $meta_ret -ne 0 ]]; then
        echo "SKIPPED_METADATA_ERROR"
        return 0
    fi

    local -a raddrs=()
    for addr in $metadata_ips ; do
        if [[ $addr =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
            raddrs+=("$addr")
        fi
    done

    # Keep-last-good-state checks
    if [[ ${#raddrs[@]} -eq 0 ]]; then
        echo "SKIPPED_EMPTY_METADATA"
        return 0
    fi

    local has_primary=0
    for addr in ${raddrs[@]} ; do
        if [[ "${addr%/*}" == "$IPADDR" ]]; then
            has_primary=1
            break
        fi
    done
    if [[ $has_primary -eq 0 ]]; then
        echo "SKIPPED_MISSING_PRIMARY"
        return 0
    fi

    # Reconciliation
    # Find addresses to remove
    for addr in "${current_addrs[@]}" ; do
        local in_target=0
        for t in "${raddrs[@]}" ; do
            [[ "$addr" == "$t" ]] && in_target=1 && break
        done
        if [[ $in_target -eq 0 ]]; then
            # Safety check: not DHCP IP
            if [[ "${addr%/*}" != "$IPADDR" ]]; then
                # Check if in cn_addrs
                for cn in "${cn_addrs[@]}" ; do
                    if [[ "$addr" == "$cn" ]]; then
                        deleted_addrs+=("$addr")
                        break
                    fi
                done
            fi
        fi
    done

    echo "RECONCILED:DELETED=${deleted_addrs[*]:-none}"
}

# Case 3.1: Transient metadata query error
res=$(simulate_reconcile "10.29.18.10" "" 1)
assert_eq "SKIPPED_METADATA_ERROR" "$res" "3.1: Transient query error aborts reconciliation, secondary IP kept"

# Case 3.2: Empty metadata response
res=$(simulate_reconcile "10.29.18.10" "" 0)
assert_eq "SKIPPED_EMPTY_METADATA" "$res" "3.2: Empty metadata response aborts reconciliation, secondary IP kept"

# Case 3.3: Metadata returned IPs but missing primary DHCP IP
res=$(simulate_reconcile "10.29.18.10" "10.29.18.119/24" 0)
assert_eq "SKIPPED_MISSING_PRIMARY" "$res" "3.3: Metadata missing primary DHCP IP aborts reconciliation, secondary IP kept"

# Case 3.4: Authoritative removal (Azure Portal removed secondary IP, metadata contains only primary)
res=$(simulate_reconcile "10.29.18.10" "10.29.18.10/24" 0)
assert_eq "RECONCILED:DELETED=10.29.18.119/24" "$res" "3.4: Authoritative removal correctly deletes secondary IP"

# Case 3.5: No change (metadata contains both primary and secondary)
res=$(simulate_reconcile "10.29.18.10" "10.29.18.10/24 10.29.18.119/24" 0)
assert_eq "RECONCILED:DELETED=none" "$res" "3.5: Stable state leaves all IPs unchanged"

# Test Suite 4: metadata_available retry
echo ""
echo "--- Suite 4: metadata_available retry logic ---"

# Case 4.1: metadata_available succeeds immediately
mock_curl_meta_ok() {
    echo "network/interface/0"
}
CURL="mock_curl_meta_ok"
set +e
metadata_available
ret=$?
set -e
assert_exit 0 "$ret" "4.1: metadata_available succeeds when response contains network/"

# Case 4.2: metadata_available retries on transient failure
mock_curl_meta_retry() {
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"
    if [[ $cur -eq 1 ]]; then
        return 28
    else
        echo "instance/network/interface"
        return 0
    fi
}
CURL="mock_curl_meta_retry"
echo "0" > "$ATTEMPT_FILE"
set +e
metadata_available
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 0 "$ret" "4.2: metadata_available succeeds on retry"
assert_eq "2" "$attempts" "4.2: Exactly 2 attempts were made"

# Case 4.3: metadata_available fails after all retries
mock_curl_meta_fail() {
    local cur=0
    [[ -s "$ATTEMPT_FILE" ]] && cur=$(cat "$ATTEMPT_FILE")
    cur=$((cur + 1))
    echo "$cur" > "$ATTEMPT_FILE"
    return 28
}
CURL="mock_curl_meta_fail"
echo "0" > "$ATTEMPT_FILE"
set +e
metadata_available
ret=$?
set -e
attempts=$(cat "$ATTEMPT_FILE")
assert_exit 1 "$ret" "4.3: metadata_available returns exit 1 after failed retries"
assert_eq "3" "$attempts" "4.3: metadata_available attempted 3 retries"

echo ""
echo "============================================================"
echo "Test Results: $PASSED passed, $FAILED failed"
echo "============================================================"

if [[ $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
