#!/usr/bin/env bash

set -euo pipefail

GROUP_ID="${MAVEN_GROUP_ID:-io.github.178meorg}"
ARTIFACT_ID="${MAVEN_ARTIFACT_ID:-libvlc4-all}"
CENTRAL_BASE_URL="${CENTRAL_BASE_URL:-https://central.sonatype.com}"
WAIT_SECONDS="${CENTRAL_WAIT_SECONDS:-3600}"

usage() {
    cat <<'EOF'
Usage: publish-central.sh --aar <file-or-directory> --version <version> \
    --vlc-revision <commit>

Required environment variables:
  CENTRAL_USERNAME   Central Portal user-token username
  CENTRAL_PASSWORD   Central Portal user-token password
  SIGNING_KEY        ASCII-armored GPG private key
  SIGNING_PASSWORD   GPG private-key passphrase
EOF
}

fail() {
    printf 'ERROR: %s\n' "$1" >&2
    exit 1
}

AAR_INPUT=""
VERSION=""
VLC_REVISION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --aar)
            [[ $# -ge 2 ]] || fail "--aar requires a value"
            AAR_INPUT="$2"
            shift 2
            ;;
        --version)
            [[ $# -ge 2 ]] || fail "--version requires a value"
            VERSION="$2"
            shift 2
            ;;
        --vlc-revision)
            [[ $# -ge 2 ]] || fail "--vlc-revision requires a value"
            VLC_REVISION="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            fail "unknown option: $1"
            ;;
    esac
done

[[ -n "$AAR_INPUT" ]] || fail "--aar is required"
[[ -n "$VERSION" ]] || fail "--version is required"
[[ -n "$VLC_REVISION" ]] || fail "--vlc-revision is required"
[[ "$VERSION" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || fail "invalid Maven version: $VERSION"
[[ "$VERSION" != *-SNAPSHOT ]] || fail "Maven Central does not accept SNAPSHOT versions"
[[ "$GROUP_ID" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || fail "invalid Maven groupId: $GROUP_ID"
[[ "$ARTIFACT_ID" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || fail "invalid Maven artifactId: $ARTIFACT_ID"
[[ "$VLC_REVISION" =~ ^[0-9A-Za-z._-]+$ ]] || fail "invalid VLC revision: $VLC_REVISION"

: "${CENTRAL_USERNAME:?CENTRAL_USERNAME is required}"
: "${CENTRAL_PASSWORD:?CENTRAL_PASSWORD is required}"
: "${SIGNING_KEY:?SIGNING_KEY is required}"
: "${SIGNING_PASSWORD:?SIGNING_PASSWORD is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"

command -v gpg >/dev/null 2>&1 || fail "gpg is not installed"
command -v jar >/dev/null 2>&1 || fail "jar is not installed"
command -v zip >/dev/null 2>&1 || fail "zip is not installed"
command -v unzip >/dev/null 2>&1 || fail "unzip is not installed"
command -v curl >/dev/null 2>&1 || fail "curl is not installed"
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

if [[ -f "$AAR_INPUT" ]]; then
    AAR_FILE="$AAR_INPUT"
elif [[ -d "$AAR_INPUT" ]]; then
    mapfile -t AAR_FILES < <(find "$AAR_INPUT" -type f -name '*.aar' -print | sort)
    [[ "${#AAR_FILES[@]}" -eq 1 ]] || fail "expected exactly one AAR in $AAR_INPUT"
    AAR_FILE="${AAR_FILES[0]}"
else
    fail "AAR path does not exist: $AAR_INPUT"
fi
[[ -s "$AAR_FILE" ]] || fail "AAR file is empty: $AAR_FILE"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/libvlc-central.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
chmod 700 "$WORK_DIR"

GNUPGHOME="$WORK_DIR/gnupg"
mkdir -m 700 "$GNUPGHOME"
export GNUPGHOME
printf '%s\n' "$SIGNING_KEY" | gpg --batch --import >/dev/null 2>&1 || \
    fail "could not import SIGNING_KEY"

KEY_ID="$(gpg --batch --with-colons --list-secret-keys | \
    awk -F: '$1 == "sec" { print $5; exit }')"
[[ -n "$KEY_ID" ]] || fail "SIGNING_KEY contains no secret signing key"

STAGING_ROOT="$WORK_DIR/staging"
ARTIFACT_DIR="$STAGING_ROOT/${GROUP_ID//./\/}/$ARTIFACT_ID/$VERSION"
mkdir -p "$ARTIFACT_DIR"

POM_FILE="$ARTIFACT_DIR/$ARTIFACT_ID-$VERSION.pom"
cat > "$POM_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$ARTIFACT_ID</artifactId>
  <version>$VERSION</version>
  <packaging>aar</packaging>
  <name>178me LibVLC 4 for Android</name>
  <description>LibVLC 4 Android bindings built from the 178meorg VLC fork</description>
  <url>https://github.com/178meorg/libvlcjni</url>
  <licenses>
    <license>
      <name>GNU Lesser General Public License, version 2.1</name>
      <url>https://www.gnu.org/licenses/old-licenses/lgpl-2.1.en.html</url>
      <distribution>repo</distribution>
    </license>
  </licenses>
  <developers>
    <developer>
      <id>178meorg</id>
      <name>178meorg</name>
      <url>https://github.com/178meorg</url>
    </developer>
  </developers>
  <scm>
    <connection>scm:git:https://github.com/178meorg/libvlcjni.git</connection>
    <developerConnection>scm:git:ssh://git@github.com/178meorg/libvlcjni.git</developerConnection>
    <url>https://github.com/178meorg/libvlcjni</url>
  </scm>
  <properties>
    <vlc.revision>$VLC_REVISION</vlc.revision>
  </properties>
  <dependencies>
    <dependency>
      <groupId>androidx.annotation</groupId>
      <artifactId>annotation</artifactId>
      <version>1.7.1</version>
      <scope>compile</scope>
    </dependency>
    <dependency>
      <groupId>androidx.legacy</groupId>
      <artifactId>legacy-support-v4</artifactId>
      <version>1.0.0</version>
      <scope>compile</scope>
    </dependency>
  </dependencies>
</project>
EOF

AAR_FILE_OUT="$ARTIFACT_DIR/$ARTIFACT_ID-$VERSION.aar"
cp "$AAR_FILE" "$AAR_FILE_OUT"

SOURCES_FILE="$ARTIFACT_DIR/$ARTIFACT_ID-$VERSION-sources.jar"
jar --create --file "$SOURCES_FILE" -C "$PROJECT_ROOT/libvlc/src" .

# Central accepts a placeholder javadoc jar when a project cannot generate
# JavaDoc for platform-specific sources. Keep a pointer to the project inside it.
JAVADOC_CONTENT="$WORK_DIR/javadoc-content"
mkdir -p "$JAVADOC_CONTENT"
cat > "$JAVADOC_CONTENT/README.md" <<EOF
Javadoc for $GROUP_ID:$ARTIFACT_ID:$VERSION is maintained in the project source tree:
https://github.com/178meorg/libvlcjni
EOF
JAVADOC_FILE="$ARTIFACT_DIR/$ARTIFACT_ID-$VERSION-javadoc.jar"
jar --create --file "$JAVADOC_FILE" -C "$JAVADOC_CONTENT" README.md

sign_file() {
    local file="$1"
    printf '%s' "$SIGNING_PASSWORD" | \
        gpg --batch --no-tty --yes --pinentry-mode loopback \
            --passphrase-fd 0 --local-user "$KEY_ID" \
            --armor --detach-sign "$file"
}

checksum_file() {
    local file="$1"
    md5sum "$file" | awk '{ print $1 }' > "$file.md5"
    sha1sum "$file" | awk '{ print $1 }' > "$file.sha1"
    sha256sum "$file" | awk '{ print $1 }' > "$file.sha256"
    sha512sum "$file" | awk '{ print $1 }' > "$file.sha512"
}

for file in "$POM_FILE" "$AAR_FILE_OUT" "$SOURCES_FILE" "$JAVADOC_FILE"; do
    sign_file "$file"
    checksum_file "$file"
done

BUNDLE_FILE="$WORK_DIR/$ARTIFACT_ID-$VERSION-central-bundle.zip"
(cd "$STAGING_ROOT" && zip -q -r "$BUNDLE_FILE" .)
unzip -tq "$BUNDLE_FILE"

AUTH_TOKEN="$(printf '%s:%s' "$CENTRAL_USERNAME" "$CENTRAL_PASSWORD" | base64 | tr -d '\n')"
UPLOAD_URL="$CENTRAL_BASE_URL/api/v1/publisher/upload?name=${ARTIFACT_ID}-${VERSION}&publishingType=AUTOMATIC"
UPLOAD_RESPONSE="$WORK_DIR/upload-response"
UPLOAD_CODE="$(curl --silent --show-error --retry 3 --retry-all-errors \
    --output "$UPLOAD_RESPONSE" --write-out '%{http_code}' \
    --request POST --header "Authorization: Bearer $AUTH_TOKEN" \
    --form "bundle=@$BUNDLE_FILE;type=application/octet-stream" \
    "$UPLOAD_URL")"

if [[ "$UPLOAD_CODE" != "201" ]]; then
    printf 'Central upload failed (HTTP %s):\n' "$UPLOAD_CODE" >&2
    cat "$UPLOAD_RESPONSE" >&2
    exit 1
fi

DEPLOYMENT_ID="$(tr -d '[:space:]' < "$UPLOAD_RESPONSE")"
[[ "$DEPLOYMENT_ID" =~ ^[0-9a-fA-F-]{20,}$ ]] || \
    fail "Central returned an invalid deployment ID"
printf 'Central deployment created: %s\n' "$DEPLOYMENT_ID"

STATUS_URL="$CENTRAL_BASE_URL/api/v1/publisher/status?id=$DEPLOYMENT_ID"
DEADLINE=$((SECONDS + WAIT_SECONDS))
while (( SECONDS < DEADLINE )); do
    STATUS_RESPONSE="$WORK_DIR/status-response"
    STATUS_CODE="$(curl --silent --show-error --retry 3 --retry-all-errors \
        --output "$STATUS_RESPONSE" --write-out '%{http_code}' \
        --request POST --header "Authorization: Bearer $AUTH_TOKEN" \
        "$STATUS_URL")"
    if [[ "$STATUS_CODE" != "200" ]]; then
        printf 'Central status check failed (HTTP %s):\n' "$STATUS_CODE" >&2
        cat "$STATUS_RESPONSE" >&2
        exit 1
    fi

    STATE="$(jq -r '.deploymentState // empty' "$STATUS_RESPONSE")"
    printf 'Central deployment state: %s\n' "${STATE:-unknown}"
    case "$STATE" in
        PUBLISHED)
            printf 'Published %s:%s:%s\n' "$GROUP_ID" "$ARTIFACT_ID" "$VERSION"
            exit 0
            ;;
        FAILED)
            jq -r '.errors // . // "Central reported a failed deployment"' "$STATUS_RESPONSE" >&2
            exit 1
            ;;
        VALIDATED)
            PUBLISH_URL="$CENTRAL_BASE_URL/api/v1/publisher/deployment/$DEPLOYMENT_ID"
            PUBLISH_CODE="$(curl --silent --show-error --retry 3 --retry-all-errors \
                --output "$WORK_DIR/publish-response" --write-out '%{http_code}' \
                --request POST --header "Authorization: Bearer $AUTH_TOKEN" \
                "$PUBLISH_URL")"
            [[ "$PUBLISH_CODE" == "204" ]] || {
                printf 'Central publish request failed (HTTP %s):\n' "$PUBLISH_CODE" >&2
                cat "$WORK_DIR/publish-response" >&2
                exit 1
            }
            printf 'Central accepted the deployment for publishing\n'
            sleep 15
            ;;
        PENDING|VALIDATING|PUBLISHING)
            sleep 15
            ;;
        *)
            sleep 15
            ;;
    esac
done

fail "timed out waiting for Central deployment $DEPLOYMENT_ID"
