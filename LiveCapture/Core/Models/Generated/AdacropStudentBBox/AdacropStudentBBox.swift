//
// AdacropStudentBBox.swift
//
// This file was automatically generated and should not be edited.
//

import CoreML


/// Model Prediction Input Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentBBoxInput : MLFeatureProvider {

    /// full_img as 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats
    var full_img: MLMultiArray

    var featureNames: Set<String> { ["full_img"] }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        if featureName == "full_img" {
            return MLFeatureValue(multiArray: full_img)
        }
        return nil
    }

    init(full_img: MLMultiArray) {
        self.full_img = full_img
    }

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    convenience init(full_img: MLShapedArray<Float16>) {
        self.init(full_img: MLMultiArray(full_img))
    }

}


/// Model Prediction Output Type
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentBBoxOutput : MLFeatureProvider {

    /// Source provided by CoreML
    private let provider : MLFeatureProvider

    /// bbox as 1 by 4 matrix of 16-bit floats
    var bbox: MLMultiArray {
        provider.featureValue(for: "bbox")!.multiArrayValue!
    }

    /// bbox as 1 by 4 matrix of 16-bit floats
    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    var bboxShapedArray: MLShapedArray<Float16> {
        MLShapedArray<Float16>(bbox)
    }

    var featureNames: Set<String> {
        provider.featureNames
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        provider.featureValue(for: featureName)
    }

    init(bbox: MLMultiArray) {
        self.provider = try! MLDictionaryFeatureProvider(dictionary: ["bbox" : MLFeatureValue(multiArray: bbox)])
    }

    init(features: MLFeatureProvider) {
        self.provider = features
    }
}


/// Class for model loading and prediction
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, visionOS 1.0, *)
class AdacropStudentBBox {
    let model: MLModel

    /// URL of model assuming it was installed in the same bundle as this class
    class var urlOfModelInThisBundle : URL {
        let bundle = Bundle(for: self)
        return bundle.url(forResource: "AdacropStudentBBox", withExtension:"mlmodelc")!
    }

    /**
        Construct AdacropStudentBBox instance with an existing MLModel object.

        Usually the application does not use this initializer unless it makes a subclass of AdacropStudentBBox.
        Such application may want to use `MLModel(contentsOfURL:configuration:)` and `AdacropStudentBBox.urlOfModelInThisBundle` to create a MLModel object to pass-in.

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
        Construct AdacropStudentBBox instance with explicit path to mlmodelc file
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
        Construct AdacropStudentBBox instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<AdacropStudentBBox, Error>) -> Void) {
        load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration, completionHandler: handler)
    }

    /**
        Construct AdacropStudentBBox instance asynchronously with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - configuration: the desired model configuration
    */
    class func load(configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> AdacropStudentBBox {
        try await load(contentsOf: self.urlOfModelInThisBundle, configuration: configuration)
    }

    /**
        Construct AdacropStudentBBox instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
          - handler: the completion handler to be called when the model loading completes successfully or unsuccessfully
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration(), completionHandler handler: @escaping (Swift.Result<AdacropStudentBBox, Error>) -> Void) {
        MLModel.load(contentsOf: modelURL, configuration: configuration) { result in
            switch result {
            case .failure(let error):
                handler(.failure(error))
            case .success(let model):
                handler(.success(AdacropStudentBBox(model: model)))
            }
        }
    }

    /**
        Construct AdacropStudentBBox instance asynchronously with URL of the .mlmodelc directory with optional configuration.

        Model loading may take time when the model content is not immediately available (e.g. encrypted model). Use this factory method especially when the caller is on the main thread.

        - parameters:
          - modelURL: the URL to the model
          - configuration: the desired model configuration
    */
    class func load(contentsOf modelURL: URL, configuration: MLModelConfiguration = MLModelConfiguration()) async throws -> AdacropStudentBBox {
        let model = try await MLModel.load(contentsOf: modelURL, configuration: configuration)
        return AdacropStudentBBox(model: model)
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentBBoxInput

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentBBoxOutput
    */
    func prediction(input: AdacropStudentBBoxInput) throws -> AdacropStudentBBoxOutput {
        try prediction(input: input, options: MLPredictionOptions())
    }

    /**
        Make a prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentBBoxInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentBBoxOutput
    */
    func prediction(input: AdacropStudentBBoxInput, options: MLPredictionOptions) throws -> AdacropStudentBBoxOutput {
        let outFeatures = try model.prediction(from: input, options: options)
        return AdacropStudentBBoxOutput(features: outFeatures)
    }

    /**
        Make an asynchronous prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - input: the input to the prediction as AdacropStudentBBoxInput
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentBBoxOutput
    */
    @available(macOS 14.0, iOS 17.0, tvOS 17.0, watchOS 10.0, visionOS 1.0, *)
    func prediction(input: AdacropStudentBBoxInput, options: MLPredictionOptions = MLPredictionOptions()) async throws -> AdacropStudentBBoxOutput {
        let outFeatures = try await model.prediction(from: input, options: options)
        return AdacropStudentBBoxOutput(features: outFeatures)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - full_img: 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentBBoxOutput
    */
    func prediction(full_img: MLMultiArray) throws -> AdacropStudentBBoxOutput {
        let input_ = AdacropStudentBBoxInput(full_img: full_img)
        return try prediction(input: input_)
    }

    /**
        Make a prediction using the convenience interface

        It uses the default function if the model has multiple functions.

        - parameters:
            - full_img: 1 × 3 × 224 × 224 4-dimensional array of 16-bit floats

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as AdacropStudentBBoxOutput
    */

    #if (os(macOS) || targetEnvironment(macCatalyst)) && arch(x86_64)
    @available(macOS, unavailable)
    @available(macCatalyst, unavailable)
    #else
    @available(macOS 15.0, *)
    #endif
    func prediction(full_img: MLShapedArray<Float16>) throws -> AdacropStudentBBoxOutput {
        let input_ = AdacropStudentBBoxInput(full_img: full_img)
        return try prediction(input: input_)
    }

    /**
        Make a batch prediction using the structured interface

        It uses the default function if the model has multiple functions.

        - parameters:
           - inputs: the inputs to the prediction as [AdacropStudentBBoxInput]
           - options: prediction options

        - throws: an NSError object that describes the problem

        - returns: the result of the prediction as [AdacropStudentBBoxOutput]
    */
    func predictions(inputs: [AdacropStudentBBoxInput], options: MLPredictionOptions = MLPredictionOptions()) throws -> [AdacropStudentBBoxOutput] {
        let batchIn = MLArrayBatchProvider(array: inputs)
        let batchOut = try model.predictions(from: batchIn, options: options)
        var results : [AdacropStudentBBoxOutput] = []
        results.reserveCapacity(inputs.count)
        for i in 0..<batchOut.count {
            let outProvider = batchOut.features(at: i)
            let result =  AdacropStudentBBoxOutput(features: outProvider)
            results.append(result)
        }
        return results
    }
}
