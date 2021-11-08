//
//  Photogrammetry.swift
//  ObjectCaptureModeling
//
//  Created by Mac mini on 2021/11/5.
//

import Foundation
import RealityKit
import os
import SwiftUI

private let logger = Logger(subsystem: "com.apple.sample.photogrammetry",
                            category: "Photogrammetry")

class Photogrammetry: ObservableObject {
    
    typealias Configuration = PhotogrammetrySession.Configuration
    typealias Request = PhotogrammetrySession.Request
    
    private var inputFolder: String = "/Users/macmini/Pictures/ObjectCapture"
    
    private var outputFilename: String = "/Users/macmini/Pictures/ObjectCapture"
        
    var folder: String {
        set {
            self.inputFolder = "/Users/macmini/Pictures/ObjectCapture/\(newValue)"
            self.outputFilename = "/Users/macmini/Pictures/ObjectCapture/\(newValue)"
            _folder = newValue
        }
        
        get {
            _folder
        }
    }
    
    private var _folder: String = ""
    
    var detail: Request.Detail = .preview
    
    var sampleOrdering: Configuration.SampleOrdering = .sequential
    
    var featureSensitivity: Configuration.FeatureSensitivity = .normal
    
    @Published var fractionComplete: Double = 0.0
        
    func run() {
        let inputFolderUrl = URL(fileURLWithPath: inputFolder, isDirectory: true)
        let configuration = makeConfigurationFromArguments()
        logger.log("Using configuration: \(String(describing: configuration))")
        
        var maybeSession: PhotogrammetrySession? = nil
        do {
            maybeSession = try PhotogrammetrySession(input: inputFolderUrl,
                                                     configuration: configuration)
            logger.log("Successfully created session.")
        } catch {
            logger.error("Error creating session: \(String(describing: error))")
            Foundation.exit(1)
        }
        guard let session = maybeSession else {
            Foundation.exit(1)
        }
        
        let waiter = Task {
            do {
                for try await output in session.outputs {
                    switch output {
                        case .processingComplete:
                            logger.log("Processing is complete!")
                            Foundation.exit(0)
                        case .requestError(let request, let error):
                            logger.error("Request \(String(describing: request)) had an error: \(String(describing: error))")
                        case .requestComplete(let request, let result):
                            self.handleRequestComplete(request: request, result: result)
                        case .requestProgress(let request, let fractionComplete):
                            self.handleRequestProgress(request: request, fractionComplete: fractionComplete)
                        case .inputComplete:  // data ingestion only!
                            logger.log("Data ingestion is complete.  Beginning processing...")
                        case .invalidSample(let id, let reason):
                            logger.warning("Invalid Sample! id=\(id)  reason=\"\(reason)\"")
                        case .skippedSample(let id):
                            logger.warning("Sample id=\(id) was skipped by processing.")
                        case .automaticDownsampling:
                            logger.warning("Automatic downsampling was applied!")
                        case .processingCancelled:
                            logger.warning("Processing was cancelled.")
                        @unknown default:
                            logger.error("Output: unhandled message: \(output.localizedDescription)")
                    }
                }
            } catch {
                logger.error("Output: ERROR = \(String(describing: error))")
                Foundation.exit(0)
            }
        }
        
        // The compiler may deinitialize these objects since they may appear to be
        // unused. This keeps them from being deallocated until they exit.
        withExtendedLifetime((session, waiter)) {
            // Run the main process call on the request, then enter the main run
            // loop until you get the published completion event or error.
            do {
                let request = makeRequestFromArguments()
                logger.log("Using request: \(String(describing: request))")
                try session.process(requests: [ request ])
                // Enter the infinite loop dispatcher used to process asynchronous
                // blocks on the main queue. You explicitly exit above to stop the loop.
                RunLoop.main.run()
            } catch {
                logger.critical("Process got error: \(String(describing: error))")
                Foundation.exit(1)
            }
        }
    }
    
    /// Creates the session configuration by overriding any defaults with arguments specified.
    private func makeConfigurationFromArguments() -> PhotogrammetrySession.Configuration {
        var configuration = PhotogrammetrySession.Configuration()
        configuration.sampleOrdering = sampleOrdering
        configuration.featureSensitivity = featureSensitivity
        
        return configuration
    }
    
    /// Creates a request to use based on the command-line arguments.
    private func makeRequestFromArguments() -> PhotogrammetrySession.Request {
        let outputUrl = URL(fileURLWithPath: outputFilename)
        return PhotogrammetrySession.Request.modelFile(url: outputUrl, detail: detail)
    }
    
    /// Called when the the session sends a request completed message.
    private func handleRequestComplete(request: PhotogrammetrySession.Request,
                                              result: PhotogrammetrySession.Result) {
        logger.log("Request complete: \(String(describing: request)) with result...")
        switch result {
            case .modelFile(let url):
                logger.log("\tmodelFile available at url=\(url)")
            default:
                logger.warning("\tUnexpected result: \(String(describing: result))")
        }
    }
    
    /// Called when the sessions sends a progress update message.
    private func handleRequestProgress(request: PhotogrammetrySession.Request,
                                              fractionComplete: Double) {
        DispatchQueue.main.async {
            self.fractionComplete = fractionComplete
        }

        logger.log("Progress(request = \(String(describing: request))) = \(fractionComplete)")
    }
    
}
