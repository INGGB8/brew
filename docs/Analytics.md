# Anonymous Aggregate User Behaviour Analytics

Homebrew gathers anonymous aggregate user behaviour analytics using Google Analytics (until our in-progress migration to our own InfluxDB). You will be notified the first time you run `brew update` or install Homebrew. Analytics are not enabled until after this notice is shown, to ensure that you can [opt out](Analytics.md#opting-out) without ever sending analytics data.

## Why?

Homebrew is provided free of charge and run entirely by volunteers in their spare time. As a result, we do not have the resources to do detailed user studies of Homebrew users to decide on how best to design future features and prioritise current work. Anonymous aggregate user analytics allow us to prioritise fixes and features based on how, where and when people use Homebrew. For example:

- If a formula is widely used and is failing often it will enable us to prioritise fixing that formula over others.
- Collecting the OS version allows us to decide which versions of macOS to prioritise for support and identify build failures that occur only on single versions.

## How Long?

Homebrew's anonymous user and event data have a 14 month retention period. This is the [lowest possible value for Google Analytics](https://support.google.com/analytics/answer/7667196).

## What?

Homebrew's analytics record some shared information for every event:

- The Homebrew user agent, e.g. `Homebrew/3.3.0 (Macintosh; Intel Mac OS X 10.15.6) curl/7.64.1`.
- The [Google Analytics version](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#v), i.e. `1`.
- The Homebrew [analytics tracking ID](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#tid), e.g. `UA-75654628-1`.
- A Homebrew [analytics user ID](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#cid), e.g. `1BAB65CC-FE7F-4D8C-AB45-B7DB5A6BA9CB`. This is generated by `uuidgen` and stored in the repository-specific Git configuration variable `homebrew.analyticsuuid` within `$(brew --repository)/.git/config`. This does not allow us to track individual users, but does enable us to accurately measure user counts versus event counts. The ID is specific to the Homebrew package manager, and does not permit Homebrew maintainers to e.g. track you across websites you visit.
- Whether the [Google Analytics anonymous IP setting](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#aip) is enabled, i.e. `1`.
- The Homebrew [application name](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#an), e.g. `Homebrew`.
- The Homebrew [application version](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#av), e.g. `2.5.0`.
- The Homebrew [analytics hit type](https://developers.google.com/analytics/devguides/collection/protocol/v1/parameters#t), e.g. `event`.

Homebrew's analytics records the following different events:

- An `event` hit type with the `install` event category and the Homebrew formula from a non-private GitHub tap you install plus any used options (e.g. `wget --HEAD`) as the action, and an event label (e.g. `macOS 10.15, non-/usr/local, CI`) to indicate the OS version, non-standard installation location and invocation as part of CI. This allows us to identify which formulae need fixing and where more easily.
- An `event` hit type with the `install_on_request` event category and the Homebrew formula from a non-private GitHub tap you have requested to install (e.g. when explicitly named with a `brew install`) plus options and an event label as above. This allows us to differentiate the formulae that users intend to install from those pulled in as dependencies.
- An `event` hit type with the `cask_install` event category and the Homebrew cask from a non-private GitHub tap you install as the action and an event label as above. This allows us to identify which casks need fixing and where more easily.
- An `event` hit type with the `BuildError` event category and the Homebrew formula plus options that failed to install as the action and an event label as above, e.g. `wget --HEAD` and `macOS 10.15`.

You can also view all the information that is sent by Homebrew's analytics by setting `HOMEBREW_ANALYTICS_DEBUG=1` in your environment. Please note this will also stop any analytics from being sent.

It is impossible for the Homebrew developers to match any particular event to any particular user, even if we had access to the Homebrew analytics user ID (which we do not). An example of the most user-specific information we can see from Google Analytics:

![Aggregate user analytics](assets/img/docs/analytics.png)

As far as we can tell it would be impossible for Google to match the randomly generated Homebrew-only analytics user ID to any other Google Analytics user ID. If Google turned evil the only thing they could do would be to lie about anonymising IP addresses and attempt to match users based on IP addresses.

## When/Where?

Homebrew's analytics are sent throughout Homebrew's execution to Google Analytics over HTTPS.

## Who?

Summaries of installation and error analytics are [publicly available](https://formulae.brew.sh/analytics/). A JSON API is also available. The majority of Homebrew maintainers are not granted more detailed analytics data beyond these public resources.

## How?

The code is viewable in [`analytics.rb`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.rb) and [`analytics.sh`](https://github.com/Homebrew/brew/blob/HEAD/Library/Homebrew/utils/analytics.sh). They are done in a separate background process and fail fast to avoid delaying any execution. They will fail immediately and silently if you have no network connection.

## Opting out

Homebrew analytics helps us maintainers and leaving it on is appreciated. However, if you want to opt out of Homebrew's analytics, you can set this variable in your environment:

```sh
export HOMEBREW_NO_ANALYTICS=1
```

If you are fine with analytics being sent to Homebrew's InfluxDB but not to Google Analytics, you can set:

```sh
export HOMEBREW_NO_GOOGLE_ANALYTICS=1
```

Alternatively, this will prevent analytics from ever being sent:

```sh
brew analytics off
```
