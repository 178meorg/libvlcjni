# Deploy artifacts

> The original `deploy-to-mavencentral.sh` below is the upstream VideoLAN
> OSSRH deployment helper and uses VideoLAN's signing key. It is not used for
> this fork. Use `.github/workflows/libvlc3.yml` and
> `publish-central.sh` for the `io.github.178meorg` namespace.

## This fork

After verifying the `io.github.178meorg` namespace in the Central Portal, add
`CENTRAL_USERNAME`, `CENTRAL_PASSWORD`, `SIGNING_KEY` and `SIGNING_PASSWORD`
as GitHub Actions secrets. A `libvlc-<version>` tag publishes the universal
AAR automatically. The local helper can also be used by the workflow to build
the Central bundle:

```bash
./buildsystem/maven/publish-central.sh \
    --aar path/to/libvlc-all.aar \
    --version 3.7.5-2 \
    --vlc-revision <vlc-commit>
```

The helper expects the four secrets as environment variables and waits for the
Central deployment to reach `PUBLISHED`.

## Legacy upstream deployment

The following instructions are retained only for the original VideoLAN
artifact bundle and must not be used for this fork.

### Prerequisites

### Signing

Use [this guide](https://github.com/drduh/YubiKey-Guide#configure-smartcard) to setup a yubikey with the VideoLAN maven signing key. The key id is `e8f8f982a0cd726f020ced90f4b3cd9a1faeefe8` 

### Utilities

Apache Maven is needed.

`sudo apt install maven`

### Sonatype

You have to get Sonatype credentials. To ask for it, you will have to create a JIRA account and ask to be added [here](https://issues.sonatype.org/browse/OSSRH-65611)

## Generate the artifacts

Create a git tag named `libvlc-[libvlc-version]`. The CI will generate the libvlc and medialibrary artifacts and the debug symbols. All of these files will be available to download in a zip file named `dbg.zip` attached to the pipeline.

Copy the file to this directory (`buildsystem/maven`)

## Usage

You just have to plug your yubikey and run the script

`./deploy-to-mavencentral.sh [FILE_PATH]`

The script will do the following actions:

- check if the zip exists
- unzip it
- look for the artifact versions
- let you confirm if it's all good
- let you enter your Sonatype credentials
- create a new `settings.xml` file in the current directory. /!\ If the script fails after this point, make sure you delete this file to avoid having your credentials exposed /!\
- sign and deploy the artifacts with Apache Maven
- delete the `settings.xml` file

### Release artifacts

Once the artifacts have been deployed, you still need to release the repository.

- Go to the [Nexus Repository Manager](https://s01.oss.sonatype.org/)
- Login with your credentials
- Navigate to `Build Promotion` / `Staging Repositories`
- Select the `org.videolan` repository

![Nexus Repository Manager interface](images/nexus.png)

- Close it
- Wait for it to be closed
- Release it

When it's done, the artifacts should be available in Maven Central within a few minutes. To verify, you can navigate to:
- [libvlc](https://repo1.maven.org/maven2/org/videolan/android/libvlc-all/)
- [medialibrary](https://repo1.maven.org/maven2/org/videolan/android/medialibrary-all/)

After a few hours, they should also be available in the [Maven Search Engine](https://search.maven.org/search?q=g:org.videolan.android)
