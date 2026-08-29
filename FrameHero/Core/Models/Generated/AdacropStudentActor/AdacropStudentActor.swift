//
// AdacropStudentActor.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentActorInput : MLFeatureProvider {

    /// crop_img as 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats
    var crop_img: MLMultiArray

    /// state_workaround as 1 by 4 matrix of 16-bit floats
    var state_workaround: MLMultiArray

    var featureNames: Set<String> { ["crop_img", "state_workaround"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "crop_img" {
            return MLFeatureValue(multiArray: crop_img)
        }
        if featureName == "state_workaround" {
            return MLFeatureValue(multiArray: state_workaround)
        }
        return nil
    }

    init(crop_img: MLMultiArray, state_workaround: MLMultiArray) {
        self.crop_img = crop_img
        self.state_workaround = state_workaround
    }

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    convenience init(crop_img: MLShapedArray<Float16>, state_workaround: MLShapedArray<Float16>) {
        self.init(crop_img: MLMultiArray(crop_img), state_workaround: MLMultiArray(state_workaround))
    }

}


/// Model Prediction Output Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentActorOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// action_probs as 1 by 7 matrix of 16-bit floats
    var action_probs: MLMultiArray {
        provider.featureValue(for: "action_probs")!.multiArrayValue!
    }

    /// action_probs as 1 by 7 matrix of 16-bit floats
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    var action_probsShapedArray: MLShapedArray<Float16> {
        MLShapedArray<Float16>(action_probs)
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(action_probs: MLMultiArray) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["action_probs" : MLFeatureValue(multiArray: action_probs)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentActor {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "AdacropStudentActor", withExtension:"mlmodelc")!
    }

    /**
        Construct AdacropStudentActor instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of AdacropStudentActor.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `AdacropStudentActor.urlOfModelInThisBundle` to create a MLModel object to pass-in.

        - parameters:
          - model: MLModel object
    */
    init(model: MLModel) {
        self.model = model
    }

    /**
        Construct a model with configuration

        - parameters:
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(configuration: MLModelConfiguration = MLModelConfiguration()) throws {
        try self.init(contentsOf: type(of:self).urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct AdacropStudentActor instance with explicit path to mlmodelc file
        - parameters:
           - modelURL: the file url of the model

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL) throws {
        try self.init(model: MLModel(contentsOf: modelURL))
    }

    /**
        Construct a model with URL of the .mlmodelc directory and configuration

        - parameters:
           - modelURL: the file url of the model
           - configuration: the desired model configuration

        - throws: an NSError object that describes the problem
    */
    convenience init(contentsOf modelURL: URL, configuration: MLModelConfiguration) throws {
        try self.init(model: MLModel(contentsOf: modelURL, configuration: configuration))
    }

    /**
        Construct AdacropStudentActor instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<AdacropStudentActor, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct AdacropStudentActor instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> AdacropStudentActor {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct AdacropStudentActor instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<AdacropStudentActor, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(AdacropStudentActor(model: model)))
            }
        }
    }

    /**
        Construct AdacropStudentActor instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> AdacropStudentActor {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return AdacropStudentActor(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentActorInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentActorOutput
    */
    func prediction(input: AdacropStudentActorInput) throws -> AdacropStudentActorOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentActorInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentActorOutput
    */
    func prediction(input: AdacropStudentActorInput, options: MLPredictionOptions) throws -> AdacropStudentActorOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return AdacropStudentActorOutput(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentActorInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentActorOutput
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: AdacropStudentActorInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> AdacropStudentActorOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return AdacropStudentActorOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - crop_img: 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats
            - state_workaround: 1 by 4 matrix of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentActorOutput
    */
    func prediction(crop_img: MLMultiArray, state_workaround: MLMultiArray) throws -> AdacropStudentActorOutput {
        let input_ = AdacropStudentActorInput(crop_img: crop_img, state_workaround: state_workaround)
        return try prediction(input: input_)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - crop_img: 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats
            - state_workaround: 1 by 4 matrix of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentActorOutput
    */

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    func prediction(crop_img: MLShapedArray<Float16>, state_workaround: MLShapedArray<Float16>) throws -> AdacropStudentActorOutput {
        let input_ = AdacropStudentActorInput(crop_img: crop_img, state_workaround: state_workaround)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [AdacropStudentActorInput]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [AdacropStudentActorOutput]
    */
    func predictions(inputs: [AdacropStudentActorInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [AdacropStudentActorOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [AdacropStudentActorOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  AdacropStudentActorOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
