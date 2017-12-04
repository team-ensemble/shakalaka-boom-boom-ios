# Shakalaka Boom Boom
Shakalaka Boom Boom is an A.I. experiment which creates a magical experience by converting anything drawn on a mobile canvas into a real object in augmented reality world. To get better picture about the project, check out the video below

[![Shakalaka Boom Boom Video](https://img.youtube.com/vi/nWA-mP8DAiA/0.jpg)](https://www.youtube.com/watch?v=nWA-mP8DAiA)

## About this repository
This repository contains the code for the Shakalaka Boom Boom experiment iOS app only.

## Installation instructions
You will need Xcode 9.1 and an actual ARKit compatible iOS device to run the project. Just update the `serverURL` constant in the project, then build and run it, you are ready to go!

### Changing server URL
To get the server up and running follow the instructions on the [Shakalaka Boom Boom server](https://github.com/team-ensemble/shakalaka-boom-boom-server) repository. Once the local server is running, fetch it's URL and update it in the Xcode project.
For example if the server is up and running at `https://abcdefgh.ngrok.io` then replace the `YOUR_SERVER_URL` in the [GeneralConstants.swift](ShakalakaBoomBoom/GeneralConstants.swift) file with actual server URL as follows
```
static let serverURL = "https://abcdefgh.ngrok.io/"
```

## Usage instructions
Once you have the iOS app installed, just draw one of the supported items on the canvas and boom! Find that object placed in the AR World.
