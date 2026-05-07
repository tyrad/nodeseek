fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios tests

```sh
[bundle exec] fastlane ios tests
```

Run the CI test subset

### ios build

```sh
[bundle exec] fastlane ios build
```

Build an App Store archive without uploading

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Build and upload a public-source TestFlight build

### ios app_store_metadata

```sh
[bundle exec] fastlane ios app_store_metadata
```

Upload App Store basic metadata without uploading a binary or submitting for review

### ios app_privacy

```sh
[bundle exec] fastlane ios app_privacy
```

Upload App Privacy answers to App Store Connect

### ios app_store_screenshots

```sh
[bundle exec] fastlane ios app_store_screenshots
```

Upload App Store screenshots without uploading a binary or submitting for review

### ios app_store_info

```sh
[bundle exec] fastlane ios app_store_info
```

Upload App Store basic metadata and App Privacy answers

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
