/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main view controller for the AR experience.
*/


import ARKit
import Photos

enum AppStatus: Int {
    case canvas
    case arview
}

enum ObjectType: String {
    case chair = "chair"
    case vase = "vase"
    case lamp = "lamp"
    case candle = "candle"
    case cup = "cup"
}

enum StatusType: String {
    case success = "success"
    case failure = "error"
}

class ViewController: UIViewController, ARSCNViewDelegate, UIPopoverPresentationControllerDelegate, UITextFieldDelegate, VirtualObjectSelectionViewControllerDelegate {
    
    @IBOutlet weak var vibranceView: TranslucentView!
    @IBOutlet weak var canvasView: UIView!
    @IBOutlet var sceneView: ARSCNView!
    @IBOutlet weak var drawingCanvas: DrawView!
    @IBOutlet weak var resultView: UIView!
    @IBOutlet weak var speechField: UILabel!
    @IBOutlet weak var resultViewBottomconstraint: NSLayoutConstraint!
    @IBOutlet weak var feedbackImageView: UIImageView!
    @IBOutlet weak var feedbackTextField: UITextField!
    @IBOutlet weak var sendFeedback: UIButton!
    @IBOutlet weak var cancelFeedbackButton: UIButton!
    @IBOutlet weak var feedbackEntryViewBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var customTabBarView: UIView!
    @IBOutlet weak var walkthroughVisualEffectView: UIVisualEffectView!
    
    var image: UIImage!
    var overViewType: AppStatus = .arview
    var objectKind: ObjectType = .chair
    var status: StatusType = .failure
    var err: String!
    let spinner = UIActivityIndicatorView()
    
    // MARK: - Main Setup & View Controller methods
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let vibrant = TranslucentView()
        vibrant.setTranslucentProperties(blurType: BlurType.darkBlur, vibrancyRequired: true)
        vibranceView.addSubview(vibrant)
        feedbackTextField.delegate = self
        setupBaseView()
        Setting.registerDefaults()
        setupScene()
        setupFocusSquare()
        updateSettings()
        resetVirtualObject()
    }
    
    fileprivate func setupBaseView() {
        feedbackImageView.isHidden = true
        feedbackTextField.isHidden = true
        feedbackTextField.resignFirstResponder()
        sendFeedback.isHidden = true
        cancelFeedbackButton.isHidden = true
        DispatchQueue.main.async {
            switch self.overViewType {
            case .canvas:
                self.canvasView.isUserInteractionEnabled = true
                self.canvasView.isHidden = false
                self.vibranceView.isHidden = false
                self.clearCanvas()
                self.drawingCanvas.isHidden = false
                self.resultView.isHidden = true
            case .arview:
                self.canvasView.isUserInteractionEnabled = false
                self.canvasView.isHidden = true
                self.vibranceView.isHidden = true
                self.drawingCanvas.isHidden = true
                self.clearCanvas()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // Prevent the screen from being dimmed after a while.
        UIApplication.shared.isIdleTimerDisabled = true
        
        // Start the ARSession.
        restartPlaneDetection()
        setupBaseView()
        
        // Get notifications about keyboard activity
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillShow), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(ViewController.keyboardWillHide), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        session.pause()
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }
    
    @objc func keyboardWillShow(notification: NSNotification) {
        var userInfo = notification.userInfo!
        let keyboardScreenEndFrame = (userInfo[UIKeyboardFrameEndUserInfoKey] as! NSValue).cgRectValue
        let keyboardViewEndFrame = view.convert(keyboardScreenEndFrame, from: view.window)
        let changeInHeight = keyboardViewEndFrame.height - customTabBarView.frame.height
        UIView.animate(withDuration: 2.0) {
            self.feedbackEntryViewBottomConstraint.constant = changeInHeight
        }
    }
    
    @objc func keyboardWillHide(notification:NSNotification) {
        UIView.animate(withDuration: 2.0) {
            self.feedbackEntryViewBottomConstraint.constant = 0
        }
    }
    
    // MARK: - ARKit / ARSCNView
    
    let session = ARSession()
    var sessionConfig: ARConfiguration = ARWorldTrackingConfiguration()
    var use3DOFTracking = false {
        didSet {
            if use3DOFTracking {
                sessionConfig = AROrientationTrackingConfiguration()
            }
            sessionConfig.isLightEstimationEnabled = UserDefaults.standard.bool(for: .ambientLightEstimation)
            session.run(sessionConfig)
        }
    }
    var use3DOFTrackingFallback = false
    var screenCenter: CGPoint?
    
    func setupScene() {
        // Set up sceneView
        sceneView.delegate = self
        sceneView.session = session
        sceneView.antialiasingMode = .multisampling4X
        sceneView.automaticallyUpdatesLighting = false
        
        sceneView.preferredFramesPerSecond = 60
        sceneView.contentScaleFactor = 1.3
        
        enableEnvironmentMapWithIntensity(25.0)
        
        DispatchQueue.main.async {
            self.screenCenter = self.sceneView.bounds.mid
        }
        
        if let camera = sceneView.pointOfView?.camera {
            camera.wantsHDR = true
            camera.wantsExposureAdaptation = true
            camera.exposureOffset = -1
            camera.minimumExposure = -1
        }
    }
    
    func enableEnvironmentMapWithIntensity(_ intensity: CGFloat) {
        if sceneView.scene.lightingEnvironment.contents == nil {
            if let environmentMap = UIImage(named: "Models.scnassets/sharedImages/environment_blur.exr") {
                sceneView.scene.lightingEnvironment.contents = environmentMap
            }
        }
        sceneView.scene.lightingEnvironment.intensity = intensity
    }
    
    // MARK: - Session
    
    func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"
    }
    
    func createBodyWithParameters(parameters: [String: String]?, filePathKey: String?, imageDataKey: NSData, boundary: String) -> NSData {
        let body = NSMutableData()
        
        if parameters != nil {
            for (key, value) in parameters! {
                body.appendString("--\(boundary)\r\n")
                body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
                body.appendString("\(value)\r\n")
            }
        }
        
        let randomString = NSUUID().uuidString
        let filename = "\(randomString).jpg"
        let mimetype = "image/jpg"
        
        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        body.appendString("Content-Type: \(mimetype)\r\n\r\n")
        body.append(imageDataKey as Data)
        body.appendString("\r\n")
        body.appendString("--\(boundary)--\r\n")
        
        return body
    }
    
    func myImageUploadRequest() {
        let myUrl = NSURL(string: GeneralConstants.serverURL + GeneralConstants.uploadApi)
        
        let request = NSMutableURLRequest(url:myUrl! as URL)
        request.httpMethod = "POST"
        
        let param = [
            "firstName": "A",
            "lastName": "B",
            "userId": "007"
        ]
        
        let boundary = generateBoundaryString()
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let imageData = UIImageJPEGRepresentation(image, 1)
        if imageData == nil {
            return
        }
        
        request.httpBody = createBodyWithParameters(parameters: param, filePathKey: "file", imageDataKey: imageData! as NSData, boundary: boundary) as Data
        
        self.task(request)
    }
    
    func task(_ request: NSMutableURLRequest) {
        let task = URLSession.shared.dataTask(with: request as URLRequest) {
            data, response, error in
            DispatchQueue.main.async {
                self.resultView.isHidden = false
                self.resultViewBottomconstraint.constant = 5
                
                if error != nil {
                    self.stopSpinner()
                    self.handleRespnseViews()
                    self.speechField.text = error?.localizedDescription
                    print("error=\(String(describing: error))")
                    return
                }
                
                // Print out response object
                print("******* response = \(String(describing: response))")
                
                // Print out reponse body
                let responseString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                print("****** response data = \(responseString!)")
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as! [String: Any]
                    let objStatus = json["status"] as? String
                    if let objStatus = objStatus {
                        switch objStatus {
                        case "success":
                            self.status = .success
                        case "error":
                            self.status = .failure
                        default:
                            self.status = .failure
                        }
                        self.stopSpinner()
                        if self.status == .success {
                            let obj = json["category"] as? String ?? ""
                            self.setObject(type: obj)
                            DispatchQueue.main.async {
                                self.handleRespnseViews()
                                self.vibranceView.isHidden = true
                                self.speechField.text = "I think you want a " + obj + ".\nHere you go...😃"
                            }
                        } else {
                            self.err = json["message"] as? String ?? "Something is wrong."
                            self.handleResponse(false)
                            DispatchQueue.main.async {
                                self.handleRespnseViews()
                                self.speechField.text = GeneralConstants.failedResponseMsg
                                // Handle failure
                                UIView.animate(withDuration: 0.5, animations: {
                                    self.resultViewBottomconstraint.constant = 450
                                    self.feedbackImageView.isHidden = false
                                    self.feedbackTextField.isHidden = false
                                    self.sendFeedback.isHidden = false
                                    self.cancelFeedbackButton.isHidden = false
                                    self.canvasView.isUserInteractionEnabled = true
                                    self.feedbackTextField.becomeFirstResponder()
                                })
                            }
                        }
                    }
                } catch {
                    print(error)
                    self.stopSpinner()
                    DispatchQueue.main.async {
                        self.handleRespnseViews()
                        self.speechField.text = GeneralConstants.generalErrorMsg
                    }
                    self.restartPlaneDetection()
                }
            }
        }
        task.resume()
    }
    
    func showFeedbackAlert() {
        let ac = UIAlertController(title: "Hey!", message: "Please assign a tag to your sketch.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
    }
    
    @IBAction func sendFeedBackSelected(_ sender: UIButton) {
        if self.feedbackTextField.text?.isEmpty ?? true {
            showFeedbackAlert()
        } else {
            let isEmpty = self.feedbackTextField.text?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            if isEmpty! {
                showFeedbackAlert()
            } else {
                self.setupFeedBack()
                self.view.endEditing(true)
            }
        }
    }
    
    @IBAction func cancelFeedbackButtonTouched() {
        overViewType = .arview
        setupBaseView()
    }
    
    func feedBackTask(_ request: NSMutableURLRequest) {
        let task = URLSession.shared.dataTask(with: request as URLRequest) {
            data, response, error in
            DispatchQueue.main.async {
                self.resultView.isHidden = false
                
                if error != nil {
                    print("error=\(String(describing: error))")
                    return
                }
                
                // Print out response object
                print("******* response = \(String(describing: response))")
                
                // Print out reponse body
                let responseString = NSString(data: data!, encoding: String.Encoding.utf8.rawValue)
                print("****** response data = \(responseString!)")
                
                do {
                    let json = try JSONSerialization.jsonObject(with: data!, options: .allowFragments) as! [String:Any]
                    let objStatus = json["status"] as? String
                    if let objStatus = objStatus {
                        switch objStatus {
                        case "success":
                            self.status = .success
                        case "error":
                            self.status = .failure
                        default:
                            self.status = .failure
                        }
                        self.stopSpinner()
                        if self.status == .success {
                            DispatchQueue.main.async {
                                self.speechField.text = "Feedback captured, thank you."
                                self.feedbackTextField.isHidden = true
                                self.sendFeedback.isHidden = true
                                self.cancelFeedbackButton.isHidden = true
                                self.feedbackImageView.isHidden = true
                            }
                        } else {
                            self.err = json["message"] as? String ?? "Something is wrong."
                            DispatchQueue.main.async {
                                self.speechField.text = "Oops!"
                            }
                        }
                    }
                } catch {
                    print(error)
                    self.stopSpinner()
                    DispatchQueue.main.async {
                        self.speechField.text = GeneralConstants.generalErrorMsg
                    }
                    self.restartPlaneDetection()
                }
            }
        }
        task.resume()
    }
    
    func setupFeedBack() {
        let myUrl = NSURL(string: GeneralConstants.serverURL + GeneralConstants.feedbackApi)
        
        let request = NSMutableURLRequest(url:myUrl! as URL)
        request.httpMethod = "POST";
        let text = self.feedbackTextField.text!.trimmingCharacters(in: .whitespacesAndNewlines)
        let param = [
            "suggested_category": "\(String(describing: text))"
        ]
        
        let boundary = generateBoundaryString()
        
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        let imageData = UIImageJPEGRepresentation(image, 1)
        
        if imageData == nil {
            return
        }
        
        request.httpBody = createBodyWithParameters(parameters: param, filePathKey: "file", imageDataKey: imageData! as NSData, boundary: boundary) as Data
        
        self.feedBackTask(request)
    }
    
    func handleRespnseViews() {
        self.resultView.isHidden = false
        self.vibranceView.isHidden = false
        self.drawingCanvas.isHidden = true
        self.canvasView.isHidden = false
    }
    
    // MARK: - Handle AR
    
    func setObject( type: String) {
        switch type {
        case ObjectType.candle.rawValue:
            self.objectKind = .candle
        case ObjectType.chair.rawValue:
            self.objectKind = .chair
        case ObjectType.vase.rawValue:
            self.objectKind = .vase
        case ObjectType.lamp.rawValue:
            self.objectKind = .lamp
        case ObjectType.cup.rawValue:
            self.objectKind = .cup
        default:
            self.objectKind = .cup
        }
        self.handleSuccess()
    }
    
    func handleSuccess() {
        var index: Int!
        switch self.objectKind {
        case ObjectType.candle:
            index = 0
        case ObjectType.chair:
            index = 4
        case ObjectType.vase:
            index = 2
        case ObjectType.lamp:
            index = 3
        case ObjectType.cup:
            index = 1
        }
        loadVirtualObject(at: index)
    }
    
    // MARK: - Button Action
    
    @IBAction func canvasSelected(_ sender: UIButton) {
        self.overViewType = .canvas
        resetVirtualObject()
        setupBaseView()
    }
    
    @IBAction func clearClicked(_ sender: UIButton) {
        clearCanvas()
    }
    
    func clearCanvas() {
        drawingCanvas.clear()
        feedbackImageView.image = nil
        feedbackTextField.text = nil
        feedbackTextField.resignFirstResponder()
    }
    
    @IBAction func closeClicked(_ sender: UIButton) {
        overViewType = .arview
        setupBaseView()
    }
    
    @IBAction func sendClicked(_ sender: UIButton) {
        // Show progress indicator
        DispatchQueue.main.async {
            self.spinner.center = self.sceneView.center
            self.spinner.bounds.size = CGSize(width: 50, height: 50)
            self.sceneView.addSubview(self.spinner)
            self.spinner.startAnimating()
        }
        
        if let capturedImage = drawingCanvas.captureImage() {
            image = capturedImage
            feedbackImageView.image = image
            PHPhotoLibrary.requestAuthorization { status in
                switch status {
                case .authorized:
                    DispatchQueue.main.async {
                        UIImageWriteToSavedPhotosAlbum(capturedImage, self, #selector(self.image(_:didFinishSavingWithError:contextInfo:)), nil)
                        self.overViewType = .arview
                        self.setupBaseView()
                    }
                case .restricted:
                    self.stopSpinner()
                    self.handleResponse(false)
                case .denied:
                    self.stopSpinner()
                    self.handleResponse(false)
                default:
                    self.stopSpinner()
                    // Place for .notDetermined - in this callback status is already determined so should never get here
                    break
                }
            }
        } else {
            let ac = UIAlertController(title: "Hey!", message: "Draw something, at least!", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
            self.stopSpinner()
            self.resetVirtualObject()
            canvasView.isHidden = false
            self.vibranceView.isHidden = false
        }
    }
    
    func stopSpinner() {
        DispatchQueue.main.async {
            self.spinner.stopAnimating()
        }
    }
    
    @IBAction func helpButtonTouched(_ sender: UIButton) {
        if sender.image(for: .normal) == #imageLiteral(resourceName: "HelpIcon") {
            sender.setImage(#imageLiteral(resourceName: "shape"), for: .normal)
        } else {
            sender.setImage(#imageLiteral(resourceName: "HelpIcon"), for: .normal)
        }
        walkthroughVisualEffectView.isHidden = !walkthroughVisualEffectView.isHidden
    }
    
    @IBAction func tapGestureRecognized(_ sender: UITapGestureRecognizer) {
        print("tapGestureRecognized")
    }
    
    //MARK: - Add image to Library
    
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let _ = error {
            handleResponse(false)
            self.stopSpinner()
        } else {
            myImageUploadRequest()
        }
    }
    
    //MARK: - Helper Methods
    
    func handleResponse(_ isSuccess: Bool = false) {
        if isSuccess {
            let ac = UIAlertController(title: "Saved!", message: "Your altered image has been saved to your photos.", preferredStyle: .alert)
            ac.addAction(UIAlertAction(title: "OK", style: .default))
            present(ac, animated: true)
        } else {
            DispatchQueue.main.async {
                self.handleRespnseViews()
                self.speechField.text = "Something is not right."
            }
        }
    }
    
    // MARK: - ARSCNViewDelegate
    
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        refreshFeaturePoints()
        
        DispatchQueue.main.async {
            self.updateFocusSquare()
            self.hitTestVisualization?.render()
            
            // If light estimation is enabled, update the intensity of the model's lights and the environment map
            if let lightEstimate = self.session.currentFrame?.lightEstimate {
                self.enableEnvironmentMapWithIntensity(lightEstimate.ambientIntensity / 40)
            } else {
                self.enableEnvironmentMapWithIntensity(25)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.addPlane(node: node, anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.updatePlane(anchor: planeAnchor)
                self.checkIfObjectShouldMoveOntoPlane(anchor: planeAnchor)
            }
        }
    }
    
    func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
        DispatchQueue.main.async {
            if let planeAnchor = anchor as? ARPlaneAnchor {
                self.removePlane(anchor: planeAnchor)
            }
        }
    }
    
    var trackingFallbackTimer: Timer?
    
    func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        
        switch camera.trackingState {
        case .notAvailable:
            break
        case .limited:
            if use3DOFTrackingFallback {
                // After 10 seconds of limited quality, fall back to 3DOF mode.
                trackingFallbackTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: false, block: { _ in
                    self.use3DOFTracking = true
                    self.trackingFallbackTimer?.invalidate()
                    self.trackingFallbackTimer = nil
                })
            }
        case .normal:
            if use3DOFTrackingFallback && trackingFallbackTimer != nil {
                trackingFallbackTimer!.invalidate()
                trackingFallbackTimer = nil
            }
        }
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        
        guard let arError = error as? ARError else { return }
        
        let nsError = error as NSError
        var sessionErrorMsg = "\(nsError.localizedDescription) \(nsError.localizedFailureReason ?? "")"
        if let recoveryOptions = nsError.localizedRecoveryOptions {
            for option in recoveryOptions {
                sessionErrorMsg.append("\(option).")
            }
        }
        
        let isRecoverable = (arError.code == .worldTrackingFailed)
        if isRecoverable {
            sessionErrorMsg += "\nYou can try resetting the session or quit the application."
        } else {
            sessionErrorMsg += "\nThis is an unrecoverable error that requires to quit the application."
        }
        
        displayErrorMessage(title: "We're sorry!", message: sessionErrorMsg, allowRestart: isRecoverable)
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        session.run(sessionConfig, options: [.resetTracking, .removeExistingAnchors])
        restartExperience(self)
    }
    
    // MARK: - Ambient Light Estimation
    
    func toggleAmbientLightEstimation(_ enabled: Bool) {
        
        if enabled {
            if !sessionConfig.isLightEstimationEnabled {
                // Turn on light estimation
                sessionConfig.isLightEstimationEnabled = true
                session.run(sessionConfig)
            }
        } else {
            if sessionConfig.isLightEstimationEnabled {
                // Turn off light estimation
                sessionConfig.isLightEstimationEnabled = false
                session.run(sessionConfig)
            }
        }
    }
    
    // MARK: - Gesture Recognizers
    
    var currentGesture: Gesture?
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        self.view.endEditing(true)
        guard let object = virtualObject else {
            return
        }
        
        if currentGesture == nil {
            currentGesture = Gesture.startGestureFromTouches(touches, self.sceneView, object)
        } else {
            currentGesture = currentGesture!.updateGestureFromTouches(touches, .touchBegan)
        }
        
        displayVirtualObjectTransform()
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if virtualObject == nil {
            return
        }
        currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchMoved)
        displayVirtualObjectTransform()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if virtualObject == nil {
            return
        }
        
        currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchEnded)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if virtualObject == nil {
            return
        }
        currentGesture = currentGesture?.updateGestureFromTouches(touches, .touchCancelled)
    }
    
    // MARK: - Virtual Object Manipulation
    
    func displayVirtualObjectTransform() {
        
        guard let object = virtualObject, let cameraTransform = session.currentFrame?.camera.transform else {
            return
        }
        
        // Output the current translation, rotation & scale of the virtual object as text.
        
        let cameraPos = SCNVector3.positionFromTransform(cameraTransform)
        let vectorToCamera = cameraPos - object.position
        
        _ = vectorToCamera.length()
        
        var angleDegrees = Int(((object.eulerAngles.y) * 180) / Float.pi) % 360
        if angleDegrees < 0 {
            angleDegrees += 360
        }
    }
    
    func moveVirtualObjectToPosition(_ pos: SCNVector3?, _ instantly: Bool, _ filterPosition: Bool) {
        
        guard let newPosition = pos else {
            // Reset the content selection in the menu only if the content has not yet been initially placed.
            if virtualObject == nil {
                resetVirtualObject()
            }
            return
        }
        
        if instantly {
            setNewVirtualObjectPosition(newPosition)
        } else {
            updateVirtualObjectPosition(newPosition, filterPosition)
        }
    }
    
    var dragOnInfinitePlanesEnabled = false
    
    func worldPositionFromScreenPosition(_ position: CGPoint,
                                         objectPos: SCNVector3?,
                                         infinitePlane: Bool = false) -> (position: SCNVector3?, planeAnchor: ARPlaneAnchor?, hitAPlane: Bool) {
        
        // -------------------------------------------------------------------------------
        // 1. Always do a hit test against exisiting plane anchors first.
        //    (If any such anchors exist & only within their extents.)
        
        let planeHitTestResults = sceneView.hitTest(position, types: .existingPlaneUsingExtent)
        if let result = planeHitTestResults.first {
            
            let planeHitTestPosition = SCNVector3.positionFromTransform(result.worldTransform)
            let planeAnchor = result.anchor
            
            // Return immediately - this is the best possible outcome.
            return (planeHitTestPosition, planeAnchor as? ARPlaneAnchor, true)
        }
        
        // -------------------------------------------------------------------------------
        // 2. Collect more information about the environment by hit testing against
        //    the feature point cloud, but do not return the result yet.
        
        var featureHitTestPosition: SCNVector3?
        var highQualityFeatureHitTestResult = false
        
        let highQualityfeatureHitTestResults = sceneView.hitTestWithFeatures(position, coneOpeningAngleInDegrees: 18, minDistance: 0.2, maxDistance: 2.0)
        
        if !highQualityfeatureHitTestResults.isEmpty {
            let result = highQualityfeatureHitTestResults[0]
            featureHitTestPosition = result.position
            highQualityFeatureHitTestResult = true
        }
        
        // -------------------------------------------------------------------------------
        // 3. If desired or necessary (no good feature hit test result): Hit test
        //    against an infinite, horizontal plane (ignoring the real world).
        
        if (infinitePlane && dragOnInfinitePlanesEnabled) || !highQualityFeatureHitTestResult {
            
            let pointOnPlane = objectPos ?? SCNVector3Zero
            
            let pointOnInfinitePlane = sceneView.hitTestWithInfiniteHorizontalPlane(position, pointOnPlane)
            if pointOnInfinitePlane != nil {
                return (pointOnInfinitePlane, nil, true)
            }
        }
        
        // -------------------------------------------------------------------------------
        // 4. If available, return the result of the hit test against high quality
        //    features if the hit tests against infinite planes were skipped or no
        //    infinite plane was hit.
        
        if highQualityFeatureHitTestResult {
            return (featureHitTestPosition, nil, false)
        }
        
        // -------------------------------------------------------------------------------
        // 5. As a last resort, perform a second, unfiltered hit test against features.
        //    If there are no features in the scene, the result returned here will be nil.
        
        let unfilteredFeatureHitTestResults = sceneView.hitTestWithFeatures(position)
        if !unfilteredFeatureHitTestResults.isEmpty {
            let result = unfilteredFeatureHitTestResults[0]
            return (result.position, nil, false)
        }
        
        return (nil, nil, false)
    }
    
    // Use average of recent virtual object distances to avoid rapid changes in object scale.
    var recentVirtualObjectDistances = [CGFloat]()
    
    func setNewVirtualObjectPosition(_ pos: SCNVector3) {
        
        guard let object = virtualObject, let cameraTransform = session.currentFrame?.camera.transform else {
            return
        }
        
        recentVirtualObjectDistances.removeAll()
        
        let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
        var cameraToPosition = pos - cameraWorldPos
        
        // Limit the distance of the object from the camera to a maximum of 10 meters.
        cameraToPosition.setMaximumLength(10)
        
        object.position = cameraWorldPos + cameraToPosition
        
        if object.parent == nil {
            sceneView.scene.rootNode.addChildNode(object)
        }
    }
    
    func resetVirtualObject() {
        virtualObject?.unloadModel()
        virtualObject?.removeFromParentNode()
        virtualObject = nil
        
        // Reset selected object id for row highlighting in object selection view controller.
        UserDefaults.standard.set(-1, for: .selectedObjectID)
    }
    
    func updateVirtualObjectPosition(_ pos: SCNVector3, _ filterPosition: Bool) {
        guard let object = virtualObject else {
            return
        }
        
        guard let cameraTransform = session.currentFrame?.camera.transform else {
            return
        }
        
        let cameraWorldPos = SCNVector3.positionFromTransform(cameraTransform)
        var cameraToPosition = pos - cameraWorldPos
        
        // Limit the distance of the object from the camera to a maximum of 10 meters.
        cameraToPosition.setMaximumLength(10)
        
        // Compute the average distance of the object from the camera over the last ten
        // updates. If filterPosition is true, compute a new position for the object
        // with this average. Notice that the distance is applied to the vector from
        // the camera to the content, so it only affects the percieved distance of the
        // object - the averaging does _not_ make the content "lag".
        let hitTestResultDistance = CGFloat(cameraToPosition.length())
        
        recentVirtualObjectDistances.append(hitTestResultDistance)
        recentVirtualObjectDistances.keepLast(10)
        
        if filterPosition {
            let averageDistance = recentVirtualObjectDistances.average!
            
            cameraToPosition.setLength(Float(averageDistance))
            let averagedDistancePos = cameraWorldPos + cameraToPosition
            
            object.position = averagedDistancePos
        } else {
            object.position = cameraWorldPos + cameraToPosition
        }
    }
    
    func checkIfObjectShouldMoveOntoPlane(anchor: ARPlaneAnchor) {
        guard let object = virtualObject, let planeAnchorNode = sceneView.node(for: anchor) else {
            return
        }
        
        // Get the object's position in the plane's coordinate system.
        let objectPos = planeAnchorNode.convertPosition(object.position, from: object.parent)
        
        if objectPos.y == 0 {
            return; // The object is already on the plane - nothing to do here.
        }
        
        // Add 10% tolerance to the corners of the plane.
        let tolerance: Float = 0.1
        
        let minX: Float = anchor.center.x - anchor.extent.x / 2 - anchor.extent.x * tolerance
        let maxX: Float = anchor.center.x + anchor.extent.x / 2 + anchor.extent.x * tolerance
        let minZ: Float = anchor.center.z - anchor.extent.z / 2 - anchor.extent.z * tolerance
        let maxZ: Float = anchor.center.z + anchor.extent.z / 2 + anchor.extent.z * tolerance
        
        if objectPos.x < minX || objectPos.x > maxX || objectPos.z < minZ || objectPos.z > maxZ {
            return
        }
        
        // Drop the object onto the plane if it is near it.
        let verticalAllowance: Float = 0.03
        if objectPos.y > -verticalAllowance && objectPos.y < verticalAllowance {
            
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 0.5
            SCNTransaction.animationTimingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionEaseInEaseOut)
            object.position.y = anchor.transform.columns.3.y
            SCNTransaction.commit()
        }
    }
    
    // MARK: - Virtual Object Loading
    
    var virtualObject: VirtualObject?
    var isLoadingObject: Bool = false {
        didSet {
            DispatchQueue.main.async {
                self.settingsButton.isEnabled = !self.isLoadingObject
                self.screenshotButton.isEnabled = !self.isLoadingObject
            }
        }
    }
    
    func loadVirtualObject(at index: Int) {
        resetVirtualObject()
        
        // Load the content asynchronously.
        DispatchQueue.global().async {
            self.isLoadingObject = true
            let object = VirtualObject.availableObjects[index]
            object.viewController = self
            self.virtualObject = object
            
            object.loadModel()
            
            DispatchQueue.main.async {
                // Immediately place the object in 3D space.
                if let lastFocusSquarePos = self.focusSquare?.lastPosition {
                    self.setNewVirtualObjectPosition(lastFocusSquarePos)
                } else {
                    self.setNewVirtualObjectPosition(SCNVector3Zero)
                }
                
                // Remove progress indicator
                self.isLoadingObject = false
            }
        }
    }
    
    @IBAction func chooseObject(_ button: UIButton) {
        // Abort if we are about to load another object to avoid concurrent modifications of the scene.
        if isLoadingObject { return }
        
        let rowHeight = 45
        let popoverSize = CGSize(width: 250, height: rowHeight * VirtualObject.availableObjects.count)
        
        let objectViewController = VirtualObjectSelectionViewController(size: popoverSize)
        objectViewController.delegate = self
        objectViewController.modalPresentationStyle = .popover
        objectViewController.popoverPresentationController?.delegate = self
        self.present(objectViewController, animated: true, completion: nil)
        
        objectViewController.popoverPresentationController?.sourceView = button
        objectViewController.popoverPresentationController?.sourceRect = button.bounds
    }
    
    // MARK: - VirtualObjectSelectionViewControllerDelegate
    
    func virtualObjectSelectionViewController(_: VirtualObjectSelectionViewController, didSelectObjectAt index: Int) {
        loadVirtualObject(at: index)
    }
    
    func virtualObjectSelectionViewControllerDidDeselectObject(_: VirtualObjectSelectionViewController) {
        resetVirtualObject()
    }
    
    // MARK: - Planes
    
    var planes = [ARPlaneAnchor: Plane]()
    
    func addPlane(node: SCNNode, anchor: ARPlaneAnchor) {
        
        _ = SCNVector3.positionFromTransform(anchor.transform)
        
        let plane = Plane(anchor, showDebugVisuals)
        
        planes[anchor] = plane
        node.addChildNode(plane)
        
        if virtualObject == nil {
        }
    }
    
    func updatePlane(anchor: ARPlaneAnchor) {
        if let plane = planes[anchor] {
            plane.update(anchor)
        }
    }
    
    func removePlane(anchor: ARPlaneAnchor) {
        if let plane = planes.removeValue(forKey: anchor) {
            plane.removeFromParentNode()
        }
    }
    
    func restartPlaneDetection() {
        
        // Configure session
        if let worldSessionConfig = sessionConfig as? ARWorldTrackingConfiguration {
            worldSessionConfig.planeDetection = .horizontal
            session.run(worldSessionConfig, options: [.resetTracking, .removeExistingAnchors])
        }
        
        // Reset timer
        if trackingFallbackTimer != nil {
            trackingFallbackTimer!.invalidate()
            trackingFallbackTimer = nil
        }
        
    }
    
    // MARK: - Focus Square
    var focusSquare: FocusSquare?
    
    func setupFocusSquare() {
        focusSquare?.isHidden = true
        focusSquare?.removeFromParentNode()
        focusSquare = FocusSquare()
        sceneView.scene.rootNode.addChildNode(focusSquare!)
        
    }
    
    func updateFocusSquare() {
        guard let screenCenter = screenCenter else { return }
        
        if virtualObject != nil && sceneView.isNode(virtualObject!, insideFrustumOf: sceneView.pointOfView!) {
            focusSquare?.hide()
        } else {
            focusSquare?.unhide()
        }
        let (worldPos, planeAnchor, _) = worldPositionFromScreenPosition(screenCenter, objectPos: focusSquare?.position)
        if let worldPos = worldPos {
            focusSquare?.update(for: worldPos, planeAnchor: planeAnchor, camera: self.session.currentFrame?.camera)
        }
    }
    
    // MARK: - Hit Test Visualization
    
    var hitTestVisualization: HitTestVisualization?
    
    var showHitTestAPIVisualization = UserDefaults.standard.bool(for: .showHitTestAPI) {
        didSet {
            UserDefaults.standard.set(showHitTestAPIVisualization, for: .showHitTestAPI)
            if showHitTestAPIVisualization {
                hitTestVisualization = HitTestVisualization(sceneView: sceneView)
            } else {
                hitTestVisualization = nil
            }
        }
    }
    
    // MARK: - Debug Visualizations
    
    @IBOutlet var featurePointCountLabel: UILabel!
    
    func refreshFeaturePoints() {
        
    }
    
    var showDebugVisuals: Bool = UserDefaults.standard.bool(for: .debugMode) {
        didSet {
            featurePointCountLabel.isHidden = !showDebugVisuals
            
            planes.values.forEach { $0.showDebugVisualization(showDebugVisuals) }
            
            if showDebugVisuals {
                sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
            } else {
                sceneView.debugOptions = []
            }
            
            // Save pref
            UserDefaults.standard.set(showDebugVisuals, for: .debugMode)
        }
    }
    
    @IBOutlet weak var restartExperienceButton: UIButton!
    var restartExperienceButtonIsEnabled = true
    
    @IBAction func restartExperience(_ sender: Any) {
        
        guard restartExperienceButtonIsEnabled, !isLoadingObject else {
            return
        }
        
        DispatchQueue.main.async {
            self.restartExperienceButtonIsEnabled = false
            self.use3DOFTracking = false
            
            self.setupFocusSquare()
            self.resetVirtualObject()
            self.restartPlaneDetection()
            
            
            // Disable Restart button for five seconds in order to give the session enough time to restart.
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: {
                self.restartExperienceButtonIsEnabled = true
            })
        }
    }
    
    @IBOutlet weak var screenshotButton: UIButton!
    
    @IBAction func takeScreenshot() {
        guard screenshotButton.isEnabled else {
            return
        }
        
        let takeScreenshotBlock = {
            UIImageWriteToSavedPhotosAlbum(self.sceneView.snapshot(), nil, nil, nil)
            DispatchQueue.main.async {
                // Briefly flash the screen.
                let flashOverlay = UIView(frame: self.sceneView.frame)
                flashOverlay.backgroundColor = UIColor.white
                self.sceneView.addSubview(flashOverlay)
                UIView.animate(withDuration: 0.25, animations: {
                    flashOverlay.alpha = 0.0
                }, completion: { _ in
                    flashOverlay.removeFromSuperview()
                })
            }
        }
        
        switch PHPhotoLibrary.authorizationStatus() {
        case .authorized:
            takeScreenshotBlock()
        case .restricted, .denied:
            _ = "Photos access denied"
            _ = "Please enable Photos access for this application in Settings > Privacy to allow saving screenshots."
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization({ (authorizationStatus) in
                if authorizationStatus == .authorized {
                    takeScreenshotBlock()
                }
            })
        }
    }
    
    // MARK: - Settings
    
    @IBOutlet weak var settingsButton: UIButton!
    
    @IBAction func showSettings(_ button: UIButton) {
        self.vibranceView.isHidden = false
        canvasView.isHidden = true
        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let settingsViewController = storyboard.instantiateViewController(withIdentifier: "settingsViewController") as? SettingsViewController else {
            return
        }
        
        let barButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSettings))
        settingsViewController.navigationItem.rightBarButtonItem = barButtonItem
        settingsViewController.title = "Options"
        
        let navigationController = UINavigationController(rootViewController: settingsViewController)
        navigationController.modalPresentationStyle = .popover
        navigationController.popoverPresentationController?.delegate = self
        navigationController.preferredContentSize = CGSize(width: sceneView.bounds.size.width - 20, height: sceneView.bounds.size.height - 50)
        self.present(navigationController, animated: true, completion: nil)
        
        navigationController.popoverPresentationController?.sourceView = settingsButton
        navigationController.popoverPresentationController?.sourceRect = settingsButton.bounds
    }
    
    func popoverPresentationControllerShouldDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) -> Bool {
        self.vibranceView.isHidden = true
        return true
    }
    
    @objc
    func dismissSettings() {
        self.dismiss(animated: true, completion: nil)
        self.vibranceView.isHidden = true
        updateSettings()
    }
    
    private func updateSettings() {
        let defaults = UserDefaults.standard
        
        toggleAmbientLightEstimation(defaults.bool(for: .ambientLightEstimation))
        dragOnInfinitePlanesEnabled = defaults.bool(for: .dragOnInfinitePlanes)
        showHitTestAPIVisualization = defaults.bool(for: .showHitTestAPI)
        use3DOFTracking    = defaults.bool(for: .use3DOFTracking)
        use3DOFTrackingFallback = defaults.bool(for: .use3DOFFallback)
        for (_, plane) in planes {
            plane.updateOcclusionSetting()
        }
    }
    
    // MARK: - Error handling
    
    func displayErrorMessage(title: String, message: String, allowRestart: Bool = false) {
        // Blur the background.
        
        if allowRestart {
            // Present an alert informing about the error that has occurred.
            _ = UIAlertAction(title: "Reset", style: .default) { _ in
                self.restartExperience(self)
            }
        } else {
        }
    }
    
    // MARK: - UIPopoverPresentationControllerDelegate
    
    func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
        return .none
    }
    
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        updateSettings()
    }
}

extension NSMutableData {
    
    func appendString(_ string: String) {
        let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true)
        append(data!)
    }
}

