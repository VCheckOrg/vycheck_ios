import AVFoundation
import UIKit
@_implementationOnly import Lottie

internal class LivenessScreenViewController: UIViewController {

    // MARK: Outlets/Actions

    @IBOutlet weak var roundedView: VCheckSDKRoundedView!

    @IBOutlet weak var centerAnimHolderView: UIView!
    @IBOutlet weak var leftArrowAnimHolderView: UIView!
    @IBOutlet weak var rightArrowAnimHolderView: UIView!

    @IBOutlet weak var tvLivenessInfo: UILabel!

    @IBOutlet weak var imgMilestoneChecked: UIImageView!
    @IBOutlet weak var indicationFrame: VCheckSDKRoundedView!
    
    @IBOutlet weak var utilMeasureLayout: UIView!
    
    // MARK: - Anim properties
    private var faceAnimationView: LottieAnimationView = LottieAnimationView()
    private var arrowAnimationView: LottieAnimationView = LottieAnimationView()
    private let hapticFeedbackGenerator = UINotificationFeedbackGenerator()

    // MARK: - Member Variables (open for ext.)
    var needToShowFatalError = false
    var alertWindowTitle = "Nothing"
    var alertMessage = "Nothing"
    var viewDidAppearReached = false

    // MARK: - Camera / Scene properties (open for ext.)
    var captureDevice: AVCaptureDevice?
    var captureSession: AVCaptureSession?
    var videoFieldOfView = Float(0)
    lazy var previewLayer = CALayer()

    // MARK: - Video recording properties
    var videoRecorder = LivenessVideoRecorder.init()
    var videoStreamingPermitted: Bool = false
    var videoBuffer: CVImageBuffer?

    // MARK: - Milestone flow & logic properties

    private var milestoneFlow = StandardMilestoneFlow()

    static let LIVENESS_TIME_LIMIT_MILLIS = 14500 //max is 15000
    static let BLOCK_PIPELINE_ON_ST_SUCCESS_TIME_MILLIS = 900
    static let GESTURE_REQUEST_INTERVAL = 0.05

    private var isLivenessSessionFinished: Bool = false
    private var hasEnoughTimeForNextGesture: Bool = true
    private var livenessSessionTimeoutTimer : DispatchSourceTimer?
    private var periodicGestureCheckTimer: Timer?
    private var blockStageIndicationByUI: Bool = true
    private var blockStageChecksByRunningRequest: Bool = false  //TODO: implement on Android!

    // MARK: - Implementation & Lifecycle methods

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        self.indicationFrame.backgroundColor = UIColor.clear
        self.indicationFrame.borderColor = UIColor.systemGreen
        
        if let bc = VCheckSDK.shared.designConfig!.backgroundSecondaryColorHex {
            self.imgMilestoneChecked.backgroundColor = bc.hexToUIColor()
        }
        
        self.imgMilestoneChecked.isHidden = true
        self.indicationFrame.isHidden = true

        if !setMilestonesList() { return }
        if !setupCamera() { return }

        self.setCircleFaceOverlay()
        
        self.setupMilestoneFlow()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        self.viewDidAppearReached = true
                
        self.imgMilestoneChecked.isHidden = true
        self.indicationFrame.isHidden = true

        if needToShowFatalError {
            popupAlertWindowOnError(alertWindowTitle: alertWindowTitle, alertMessage: alertMessage)
            return
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.bounds
    }
    
    func setMilestonesList() -> Bool {
        guard let milestonesList = VCheckSDKLocalDatasource.shared.getLivenessMilestonesList()
        else {
            self.alertWindowTitle = "Milestone list is not found"
            self.alertMessage = "Probably, milestone list was not retrieved form verification service or not cached properly."
            self.needToShowFatalError = true
            return false
        }
        self.milestoneFlow.setStagesList(list: milestonesList)
        return true
    }
    
    func setupMilestoneFlow() {
        
        self.imgMilestoneChecked.isHidden = true
        self.indicationFrame.isHidden = true
        
        self.milestoneFlow.resetStages()
        
        self.isLivenessSessionFinished = false
        self.hasEnoughTimeForNextGesture = true
        self.blockStageIndicationByUI = false
        
        self.videoRecorder = LivenessVideoRecorder.init()
        self.videoStreamingPermitted = true
        self.videoRecorder.startRecording()
        
        self.livenessSessionTimeoutTimer = nil
        self.startLivenessSessionTimeoutTimer()
        
        self.tvLivenessInfo.text = "liveness_stage_check_face_pos".localized
        
        self.periodicGestureCheckTimer = Timer.scheduledTimer(timeInterval:
                        LivenessScreenViewController.GESTURE_REQUEST_INTERVAL, target: self,
                          selector: #selector(performGestureCheck), userInfo: nil, repeats: true)
        
        self.setupOrUpdateFaceAnimation(forMilestoneType: self.milestoneFlow.getCurrentStage()!)
    }
    
    @objc func performGestureCheck() {
        if (self.isLivenessSessionFinished == false) {
            if (milestoneFlow.areAllStagesPassed()) {
                self.onAllStagesPassed()
            } else {
                if (videoBuffer != nil
                    && self.hasEnoughTimeForNextGesture == true
                    && self.blockStageChecksByRunningRequest == false) {
                    self.checkStage()
                } else {
                    //print("VCheckSDK - Error: VideoBuffer is nil") //Stub
                }
            }
        }
    }
    
    func checkStage() {
        guard let frameImage: UIImage = getScreenshotFromVideoStream(videoBuffer!) else {
            print("VCheckSDK - Error: Cannot perform gesture request: either frameImage is nil!")
            return
        }
        self.blockStageChecksByRunningRequest = true
        
        ImageCompressor.compressFrame(image: frameImage, completion: { (compressedImage) in
            
            if (compressedImage == nil) {
                print("VCheckSDK - Error: Failed to compress image!")
                return
            } else {
                if let rotatedImage = compressedImage!.rotate(radians: Float(90.degreesToRadians)) {
                    
                    VCheckSDKRemoteDatasource.shared.sendLivenessGestureAttempt(frameImage: rotatedImage,
                                            gesture: self.milestoneFlow.getGestureRequestFromCurrentStage(),
                                            completion: { (data, error) in
                        if let error = error {
                            print("VCheckSDK - Error: Gesture request: Error [\(error.errorText)]")
                            self.blockStageChecksByRunningRequest = false
                            return
                        }
                        if (data?.success == true) {
                            self.milestoneFlow.incrementCurrentStage()
                            if (self.milestoneFlow.areAllStagesPassed()) {
                                self.onAllStagesPassed()
                            } else {
                                self.onStagePassed()
                            }
                        }
                        self.blockStageChecksByRunningRequest = false
                    })
                } else {
                    print("VCheckSDK - Error: Failed to rotate image as needed!")
                }
            }
        })
    }
    
    func onAllStagesPassed() {
        self.videoRecorder.stopRecording(completion: { url in
            DispatchQueue.main.async {
                
                self.imgMilestoneChecked.isHidden = true
                self.indicationFrame.isHidden = true
                
                self.periodicGestureCheckTimer?.invalidate()
                
                if (self.livenessSessionTimeoutTimer != nil) {
                    self.livenessSessionTimeoutTimer!.cancel()
                }
                
                self.hasEnoughTimeForNextGesture = false
                
                self.videoStreamingPermitted = false
                self.isLivenessSessionFinished = true
                                        
                self.hapticFeedbackGenerator.notificationOccurred(.success)
    
                self.performSegue(withIdentifier: "LivenessToVideoProcessing", sender: nil)
            }
        })
    }
    
    func onStagePassed() {
        self.hapticFeedbackGenerator.notificationOccurred(.success)
        self.delayedStageIndicationRenew()
    }

    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == "LivenessToNoTime") {
            let vc = segue.destination as! NoTimeViewController
            vc.onRepeatBlock = { result in self.renewLivenessSessionOnRetry() }
        }
        if (segue.identifier == "LivenessToVideoProcessing") {
            let vc = segue.destination as! VideoProcessingViewController
            vc.videoFileURL = self.videoRecorder.outputFileURL
            vc.livenessVC = self
        }
    }

    func renewLivenessSessionOnRetry() {
        DispatchQueue.main.async {
            // reset UI
            self.indicationFrame.alpha = 1
            self.imgMilestoneChecked.isHidden = true
            self.indicationFrame.isHidden = true
            self.faceAnimationView = LottieAnimationView()
            self.arrowAnimationView = LottieAnimationView()
            self.arrowAnimationView.stop()
            self.rightArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            self.leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            self.centerAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            // General reset logic
            self.setupMilestoneFlow()
        }
    }

    func endSessionPrematurely(performSegueWithIdentifier: String) {
        self.videoRecorder.stopRecording(completion: { url in
            DispatchQueue.main.async {
                
                self.imgMilestoneChecked.isHidden = true
                self.indicationFrame.isHidden = true
                
                self.periodicGestureCheckTimer?.invalidate()
                
                if (self.livenessSessionTimeoutTimer != nil) {
                    self.livenessSessionTimeoutTimer!.cancel()
                }
                
                self.hasEnoughTimeForNextGesture = false
                
                self.videoStreamingPermitted = false
                self.isLivenessSessionFinished = true
                                
                self.hapticFeedbackGenerator.notificationOccurred(.warning)
                
                self.performSegue(withIdentifier: performSegueWithIdentifier, sender: nil)
            }
        })
    }

    func startLivenessSessionTimeoutTimer() {
        let delay : DispatchTime = .now() + .milliseconds(LivenessScreenViewController.LIVENESS_TIME_LIMIT_MILLIS)
        if livenessSessionTimeoutTimer == nil {
            livenessSessionTimeoutTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
            livenessSessionTimeoutTimer!.schedule(deadline: delay, repeating: 0)
            livenessSessionTimeoutTimer!.setEventHandler {
                self.endSessionPrematurely(performSegueWithIdentifier: "LivenessToNoTime")
            }
            livenessSessionTimeoutTimer!.resume()
        } else {
            livenessSessionTimeoutTimer?.schedule(deadline: delay, repeating: 0)
        }
    }
}


// MARK: - UI & Animation extensions

extension LivenessScreenViewController {
    
    func setCircleFaceOverlay() {
        let frameSize = CGSize(width: self.indicationFrame.viewWidth, height: self.indicationFrame.viewHeight)
        
        let pathBigRect = UIBezierPath(rect: self.view.bounds)
        let circleCenter = CGPoint(x: self.view.viewWidth / 2, y: (self.view.viewHeight / 2) + 40) // was - 0
        let circleRadius = (min(frameSize.width, frameSize.height) / 2) - 16
        
        let pathSmallCircle = UIBezierPath(arcCenter: circleCenter,
                                           radius: circleRadius,
                                           startAngle: 0,
                                           endAngle: CGFloat.pi * 2,
                                           clockwise: true)
        pathBigRect.append(pathSmallCircle)
        
        let fillLayer = CAShapeLayer()
        fillLayer.path = pathBigRect.cgPath
        fillLayer.fillRule = CAShapeLayerFillRule.evenOdd
        
        if let bgColor = VCheckSDK.shared.designConfig!.backgroundSecondaryColorHex {
            fillLayer.fillColor = bgColor.hexToUIColor().cgColor
        } else {
            fillLayer.fillColor = UIColor(named: "CardColor", in: InternalConstants.bundle, compatibleWith: nil)?.cgColor
        }
        
        fillLayer.opacity = 1
        self.view.layer.insertSublayer(fillLayer, at: 1)

        let circlePath = UIBezierPath(arcCenter: circleCenter,
                                      radius: circleRadius,
                                      startAngle: 0,
                                      endAngle: CGFloat.pi * 2,
                                      clockwise: true)

        let shapeCircleLayer = CAShapeLayer()
        shapeCircleLayer.path = circlePath.cgPath
        shapeCircleLayer.fillColor = UIColor.clear.cgColor
        
        if let shapeColor = VCheckSDK.shared.designConfig!.sectionBorderColorHex {
            shapeCircleLayer.strokeColor = shapeColor.hexToUIColor().cgColor
        } else {
            shapeCircleLayer.strokeColor = UIColor(named: "borderColor", in: InternalConstants.bundle, compatibleWith: nil)?.cgColor
        }
        shapeCircleLayer.lineWidth = 4
        
        self.view.layer.insertSublayer(shapeCircleLayer, at: 2)
        
    }

    func delayedStageIndicationRenew() {
        DispatchQueue.main.async {

            self.blockStageIndicationByUI = true

            self.fadeSuccessFrameInThenOut(delay: 0.0)

            DispatchQueue.main.asyncAfter(deadline:
                .now() + .milliseconds(LivenessScreenViewController.BLOCK_PIPELINE_ON_ST_SUCCESS_TIME_MILLIS) ) {

                    self.imgMilestoneChecked.isHidden = true
                    self.indicationFrame.isHidden = true

                    self.blockStageIndicationByUI = false
                    
                    self.updateLivenessInfoText(forMilestoneType: self.milestoneFlow.getCurrentStage()!)
                    self.setupOrUpdateFaceAnimation(forMilestoneType: self.milestoneFlow.getCurrentStage()!)
                    self.setupOrUpdateArrowAnimation(forMilestoneType: self.milestoneFlow.getCurrentStage()!)
            }
        }
    }

    func updateLivenessInfoText(forMilestoneType: GestureMilestoneType) {
        if (forMilestoneType == GestureMilestoneType.OuterLeftHeadYawMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_face_left".localized
        } else if (forMilestoneType == GestureMilestoneType.OuterRightHeadYawMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_face_right".localized
        } else if (forMilestoneType == GestureMilestoneType.MouthOpenMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_open_mouth".localized
        } else if (forMilestoneType == GestureMilestoneType.BlinkEyesMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_blink_eyes".localized
        } else if (forMilestoneType == GestureMilestoneType.UpHeadPitchMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_face_up".localized
        } else if (forMilestoneType == GestureMilestoneType.DownHeadPitchMilestone) {
            self.tvLivenessInfo.text = "liveness_stage_face_down".localized
        } else {
            self.tvLivenessInfo.text = "liveness_stage_check_face_pos".localized
        }
    }

    func setupOrUpdateFaceAnimation(forMilestoneType: GestureMilestoneType) {

        roundedView.subviews.forEach { $0.removeFromSuperview() }

        if (forMilestoneType == GestureMilestoneType.OuterLeftHeadYawMilestone) {
            faceAnimationView = LottieAnimationView(name: "left", bundle: InternalConstants.bundle)
        } else if (forMilestoneType == GestureMilestoneType.OuterRightHeadYawMilestone) {
            faceAnimationView = LottieAnimationView(name: "right", bundle: InternalConstants.bundle)
        } else if (forMilestoneType == GestureMilestoneType.UpHeadPitchMilestone) {
            faceAnimationView = LottieAnimationView(name: "up", bundle: InternalConstants.bundle)
        } else if (forMilestoneType == GestureMilestoneType.DownHeadPitchMilestone) {
            faceAnimationView = LottieAnimationView(name: "down", bundle: InternalConstants.bundle)
        } else if (forMilestoneType == GestureMilestoneType.MouthOpenMilestone) {
            faceAnimationView = LottieAnimationView(name: "mouth", bundle: InternalConstants.bundle)
        } else if (forMilestoneType == GestureMilestoneType.BlinkEyesMilestone) {
            faceAnimationView = LottieAnimationView(name: "blink", bundle: InternalConstants.bundle)
        } else {
            faceAnimationView = LottieAnimationView(name: "face_plus_phone", bundle: InternalConstants.bundle)
        }

        faceAnimationView.contentMode = .scaleAspectFit
        faceAnimationView.translatesAutoresizingMaskIntoConstraints = false
        roundedView.addSubview(faceAnimationView)
        
        faceAnimationView.centerXAnchor.constraint(equalTo: roundedView.centerXAnchor).isActive = true
        faceAnimationView.centerYAnchor.constraint(equalTo: roundedView.centerYAnchor).isActive = true
        
        faceAnimationView.heightAnchor.constraint(equalToConstant: 100).isActive = true
        faceAnimationView.widthAnchor.constraint(equalToConstant: 100).isActive = true
    }

    func setupOrUpdateArrowAnimation(forMilestoneType: GestureMilestoneType) {

        rightArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
        leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
        centerAnimHolderView.subviews.forEach { $0.removeFromSuperview() }

        if (forMilestoneType == GestureMilestoneType.OuterLeftHeadYawMilestone) {
            
            rightArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            centerAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            
            arrowAnimationView = LottieAnimationView(name: "arrow", bundle: InternalConstants.bundle)

            arrowAnimationView.contentMode = .center
            arrowAnimationView.translatesAutoresizingMaskIntoConstraints = false
            leftArrowAnimHolderView.addSubview(arrowAnimationView)

            arrowAnimationView.centerXAnchor.constraint(equalTo: leftArrowAnimHolderView.centerXAnchor).isActive = true
            arrowAnimationView.centerYAnchor.constraint(equalTo: leftArrowAnimHolderView.centerYAnchor).isActive = true

            arrowAnimationView.heightAnchor.constraint(equalToConstant: 250).isActive = true
            arrowAnimationView.widthAnchor.constraint(equalToConstant: 250).isActive = true

            arrowAnimationView.loopMode = .loop

        } else if (forMilestoneType == GestureMilestoneType.OuterRightHeadYawMilestone) {

            leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            centerAnimHolderView.subviews.forEach { $0.removeFromSuperview() }

            arrowAnimationView = LottieAnimationView(name: "arrow", bundle: InternalConstants.bundle)

            arrowAnimationView.contentMode = .center
            arrowAnimationView.translatesAutoresizingMaskIntoConstraints = false
            rightArrowAnimHolderView.addSubview(arrowAnimationView)

            arrowAnimationView.centerXAnchor.constraint(equalTo: rightArrowAnimHolderView.centerXAnchor).isActive = true
            arrowAnimationView.centerYAnchor.constraint(equalTo: rightArrowAnimHolderView.centerYAnchor, constant: 25).isActive = true

            arrowAnimationView.heightAnchor.constraint(equalToConstant: 250).isActive = true
            arrowAnimationView.widthAnchor.constraint(equalToConstant: 250).isActive = true

            arrowAnimationView.transform = CGAffineTransform(rotationAngle: CGFloat.pi) //rotate by 180 deg.

            arrowAnimationView.loopMode = .loop

        } else if (forMilestoneType == GestureMilestoneType.UpHeadPitchMilestone) {
            
            leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            rightArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }

            arrowAnimationView = LottieAnimationView(name: "arrow", bundle: InternalConstants.bundle)

            arrowAnimationView.contentMode = .center
            arrowAnimationView.translatesAutoresizingMaskIntoConstraints = false
            centerAnimHolderView.addSubview(arrowAnimationView)

            arrowAnimationView.centerXAnchor.constraint(equalTo: centerAnimHolderView.centerXAnchor).isActive = true
            arrowAnimationView.centerYAnchor.constraint(equalTo: centerAnimHolderView.centerYAnchor).isActive = true

            arrowAnimationView.heightAnchor.constraint(equalToConstant: 250).isActive = true
            arrowAnimationView.widthAnchor.constraint(equalToConstant: 250).isActive = true

            arrowAnimationView.transform = CGAffineTransform(rotationAngle: CGFloat.pi / 2) //rotate by 90 deg.

            arrowAnimationView.loopMode = .loop
            
        } else if (forMilestoneType == GestureMilestoneType.DownHeadPitchMilestone) {
            
            leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }

            arrowAnimationView = LottieAnimationView(name: "arrow", bundle: InternalConstants.bundle)

            arrowAnimationView.contentMode = .center
            arrowAnimationView.translatesAutoresizingMaskIntoConstraints = false
            centerAnimHolderView.addSubview(arrowAnimationView)

            arrowAnimationView.centerXAnchor.constraint(equalTo: centerAnimHolderView.centerXAnchor).isActive = true
            arrowAnimationView.centerYAnchor.constraint(equalTo: centerAnimHolderView.centerYAnchor).isActive = true

            arrowAnimationView.heightAnchor.constraint(equalToConstant: 250).isActive = true
            arrowAnimationView.widthAnchor.constraint(equalToConstant: 250).isActive = true

            arrowAnimationView.transform = CGAffineTransform(rotationAngle: CGFloat.pi * 1.5) //rotate by 270 deg.

            arrowAnimationView.loopMode = .loop
        }
        else {
            arrowAnimationView = LottieAnimationView()
            arrowAnimationView.stop()
            rightArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            leftArrowAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
            centerAnimHolderView.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    func updateFaceAnimation() {
        if (self.blockStageIndicationByUI == false) {
            if (self.milestoneFlow.getCurrentStage() != GestureMilestoneType.StraightHeadCheckMilestone) {
                DispatchQueue.main.async {
                    let toProgress = self.faceAnimationView.realtimeAnimationProgress
                    if (toProgress >= 0.99) {
                        self.faceAnimationView.play(toProgress: toProgress - 0.99)
                    }
                    if (toProgress <= 0.01) {
                        self.faceAnimationView.play(toProgress: toProgress + 1)
                    }
                }
            } else {
                //workaround for broken lottie animation for sraight head check
                DispatchQueue.main.async {
                    let toProgress = self.faceAnimationView.realtimeAnimationProgress
                    if (toProgress >= 0.8) {
                        self.faceAnimationView.play(toProgress: toProgress - 0.8)
                    }
                    if (toProgress <= 0.01) {
                        self.faceAnimationView.play(toProgress: toProgress + 1)
                    }
                }
            }
        }
    }

    func updateArrowAnimation() {
        if (self.blockStageIndicationByUI == false
            && self.milestoneFlow.getCurrentStage() != GestureMilestoneType.StraightHeadCheckMilestone) {
            DispatchQueue.main.async {
                let toProgress = self.arrowAnimationView.realtimeAnimationProgress
                if (toProgress <= 0.01) {
                    self.arrowAnimationView.play(toProgress: toProgress + 1)
                }
            }
        }
    }

    func fadeSuccessFrameInThenOut(delay: TimeInterval) {
        self.imgMilestoneChecked.isHidden = true
        self.indicationFrame.isHidden = true
        
        if (self.blockStageIndicationByUI == true) {
            
            self.imgMilestoneChecked.isHidden = false
            self.indicationFrame.isHidden = false
            self.indicationFrame.alpha = 1
            DispatchQueue.main.async {
                let animationDuration = Double(LivenessScreenViewController.BLOCK_PIPELINE_ON_ST_SUCCESS_TIME_MILLIS) / 1000.0
                UIView.animate(withDuration: animationDuration, delay: delay,
                               options: [UIView.AnimationOptions.autoreverse,
                                         UIView.AnimationOptions.repeat], animations: {
                    self.indicationFrame.alpha = 0
                }, completion: nil)
            }
        }
    }
}

// MARK: - Camera output capturing delegate

extension LivenessScreenViewController: AVCaptureVideoDataOutputSampleBufferDelegate {

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {

        guard let imgBuffer: CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
        else {
            NSLog("In captureOutput, imgBuffer is nil.")
            return
        }
        
        if (self.isLivenessSessionFinished == false) {
            self.videoBuffer = imgBuffer
                        
            //MARK: Liveness Session Video Recording
            if (self.videoRecorder.outputFileURL != nil && self.videoStreamingPermitted == true) {
                self.videoRecorder.recordVideo(sampleBuffer: sampleBuffer)
            }
            
            if (blockStageIndicationByUI == false) {
                DispatchQueue.main.async {
                    self.updateFaceAnimation()
                    self.updateArrowAnimation()
                }
            }
        }
    }
    
    
    func getScreenshotFromVideoStream(_ imageBuffer: CVImageBuffer) -> UIImage? {
        var ciImage: CIImage? = nil
        if let imageBuffer = imageBuffer as CVPixelBuffer? {
            ciImage = CIImage(cvPixelBuffer: imageBuffer)
        }
        let temporaryContext = CIContext(options: nil)
        var videoImage: CGImage? = nil
        if let imageBuffer = imageBuffer as CVPixelBuffer?, let ciImage = ciImage {
            videoImage = temporaryContext.createCGImage(
                ciImage,
                from: CGRect(
                    x: 0,
                    y: 0,
                    width: CGFloat(CVPixelBufferGetWidth(imageBuffer)),
                    height: CGFloat(CVPixelBufferGetHeight(imageBuffer))))
        }
        if let cgImage = videoImage {
            return UIImage(cgImage: cgImage)
        } else {
            print("VCheckSDK - Error: Failed to convert screen into image!")
            return nil
        }
    }
}
