# Speed

An iPhone speedometer: open it and see one number, your GPS speed.

- Core Location's Doppler speed (`CLLocation.speed`) at best-for-navigation accuracy; below 0.8 m/s reads 0, and a fix
  older than 10 s goes back to dashes instead of freezing.
- Tap anywhere: km/h ↔ mph (remembered). The screen stays on while the app is open. Portrait and landscape.
- No server, no account, nothing stored or sent.

`ios/project.yml` is an XcodeGen spec. Every push to `main` runs the phone replica (`ios/UITests`, every flow on an
iPhone 17 simulator with simulated GPS fixes) and, when it passes, cloud-signs and uploads the build to TestFlight
(`.github/workflows/ios.yml`; secrets `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY`).
