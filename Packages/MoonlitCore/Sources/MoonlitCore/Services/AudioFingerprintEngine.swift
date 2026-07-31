import Accelerate
import Foundation

public struct AudioFingerprintMatch: Equatable, Sendable {
    public let offset: Double
    public let confidence: Double
    public let coverage: Double
    public let uncertainty: Double

    public init(offset: Double, confidence: Double, coverage: Double, uncertainty: Double) {
        self.offset = offset
        self.confidence = confidence
        self.coverage = coverage
        self.uncertainty = uncertainty
    }
}

public enum AudioFingerprintError: Error, Equatable, Sendable {
    case unsupportedSampleRate(expected: Int, actual: Int)
    case insufficientAudio(minimumDuration: Double, actualDuration: Double)
}

public enum AudioFingerprintEngine {
    private static let windowSize = 4_096
    private static let hopSize = 1_024
    private static let bandCount = 24
    private static let lowestFrequency = 80.0
    private static let highestFrequency = 5_000.0
    private static let rollingMedianRadius = 4
    private static let peakFloorDecibels: Float = 3
    private static let targetFrameOffsets = [11, 21, 32, 43, 53]

    public static func fingerprint(
        samples: [Float],
        sampleRate: Int = AudioFingerprintPolicy.sampleRate
    ) throws -> AudioFingerprint {
        guard sampleRate == AudioFingerprintPolicy.sampleRate else {
            throw AudioFingerprintError.unsupportedSampleRate(
                expected: AudioFingerprintPolicy.sampleRate,
                actual: sampleRate
            )
        }

        let actualDuration = Double(samples.count) / Double(sampleRate)
        guard actualDuration >= AudioFingerprintPolicy.minimumIntroDuration else {
            throw AudioFingerprintError.insufficientAudio(
                minimumDuration: AudioFingerprintPolicy.minimumIntroDuration,
                actualDuration: actualDuration
            )
        }

        let maximumSampleCount = Int(AudioFingerprintPolicy.openingWindow * Double(sampleRate))
        let sampleCount = min(samples.count, maximumSampleCount)
        let duration = Double(sampleCount) / Double(sampleRate)
        let normalizedSamples = normalizedFiniteSamples(samples.prefix(sampleCount))
        let peaks = spectralPeaks(samples: normalizedSamples, sampleRate: sampleRate)
        let landmarks = makeLandmarks(from: peaks)

        return AudioFingerprint(
            sampleRate: sampleRate,
            hopSize: hopSize,
            duration: duration,
            landmarks: landmarks
        )
    }

    public static func match(
        reference: AudioFingerprint,
        candidate: AudioFingerprint
    ) -> AudioFingerprintMatch? {
        guard reference.sampleRate == candidate.sampleRate,
              reference.hopSize == candidate.hopSize,
              reference.sampleRate > 0,
              reference.hopSize > 0,
              !reference.landmarks.isEmpty,
              !candidate.landmarks.isEmpty
        else {
            return nil
        }

        var candidateFramesByHash: [UInt32: [Int]] = [:]
        candidateFramesByHash.reserveCapacity(candidate.landmarks.count / 2)
        for landmark in candidate.landmarks {
            candidateFramesByHash[landmark.hash, default: []].append(landmark.frame)
        }

        var voteCounts: [Int: Int] = [:]
        for referenceLandmark in reference.landmarks {
            guard let candidateFrames = candidateFramesByHash[referenceLandmark.hash] else {
                continue
            }
            for candidateFrame in candidateFrames {
                let offset = candidateFrame - referenceLandmark.frame
                if offset >= 0 {
                    voteCounts[offset, default: 0] += 1
                }
            }
        }

        let centers = strongestClusterCenters(voteCounts: voteCounts, limit: 3)
        guard !centers.isEmpty else {
            return nil
        }

        let evaluated = centers.map {
            evaluateCluster(
                center: $0,
                reference: reference,
                candidateFramesByHash: candidateFramesByHash
            )
        }.sorted {
            if $0.uniqueReferenceMatches != $1.uniqueReferenceMatches {
                return $0.uniqueReferenceMatches > $1.uniqueReferenceMatches
            }
            return $0.center < $1.center
        }

        guard let winner = evaluated.first, winner.uniqueReferenceMatches > 0 else {
            return nil
        }

        let runnerUpMatches = evaluated.dropFirst().first?.uniqueReferenceMatches ?? 0
        let coverage = Double(winner.uniqueReferenceMatches)
            / Double(reference.landmarks.count)
        let runnerUpRatio = Double(runnerUpMatches)
            / Double(winner.uniqueReferenceMatches)
        let peakDominance = max(0, 1 - pow(runnerUpRatio, 3))
        let uncertainty = winner.frameSpread * Double(candidate.hopSize)
            / Double(candidate.sampleRate)
        let temporalConsistency = max(
            0,
            1 - uncertainty / AudioFingerprintPolicy.maximumUncertainty
        )
        let confidence = coverage * peakDominance * temporalConsistency
        guard coverage >= AudioFingerprintPolicy.minimumCoverage,
              confidence >= AudioFingerprintPolicy.minimumConfidence,
              uncertainty <= AudioFingerprintPolicy.maximumUncertainty
        else {
            return nil
        }

        return AudioFingerprintMatch(
            offset: Double(winner.representativeOffset * candidate.hopSize)
                / Double(candidate.sampleRate),
            confidence: confidence,
            coverage: coverage,
            uncertainty: uncertainty
        )
    }
}

private extension AudioFingerprintEngine {
    struct SpectralPeak {
        let band: Int
        let energy: Float
    }

    struct EvaluatedCluster {
        let center: Int
        let representativeOffset: Int
        let frameSpread: Double
        let uniqueReferenceMatches: Int
    }

    static func normalizedFiniteSamples<S: Collection>(_ samples: S) -> [Float]
    where S.Element == Float {
        var finiteSamples = samples.map { $0.isFinite ? $0 : 0 }
        let sumOfSquares = finiteSamples.reduce(into: 0.0) {
            $0 += Double($1) * Double($1)
        }
        let rms = sqrt(sumOfSquares / Double(max(1, finiteSamples.count)))
        guard rms > Double.leastNonzeroMagnitude else {
            return finiteSamples
        }

        let scale = Float(0.1 / rms)
        vDSP.multiply(scale, finiteSamples, result: &finiteSamples)
        return finiteSamples
    }

    static func spectralPeaks(samples: [Float], sampleRate: Int) -> [[SpectralPeak]] {
        guard samples.count >= windowSize,
              let fftSetup = vDSP_create_fftsetup(
                vDSP_Length(log2(Double(windowSize))),
                FFTRadix(kFFTRadix2)
              )
        else {
            return []
        }
        defer { vDSP_destroy_fftsetup(fftSetup) }

        var window = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&window, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        let frameCount = (samples.count - windowSize) / hopSize + 1
        let bandRanges = logarithmicBandRanges(sampleRate: sampleRate)
        var bandEnergies = [[Float]]()
        bandEnergies.reserveCapacity(frameCount)

        var frame = [Float](repeating: 0, count: windowSize)
        var real = [Float](repeating: 0, count: windowSize / 2)
        var imaginary = [Float](repeating: 0, count: windowSize / 2)
        var magnitudes = [Float](repeating: 0, count: windowSize / 2)

        for frameIndex in 0..<frameCount {
            let start = frameIndex * hopSize
            frame.withUnsafeMutableBufferPointer { frameBuffer in
                samples.withUnsafeBufferPointer { sampleBuffer in
                    frameBuffer.baseAddress?.update(
                        from: sampleBuffer.baseAddress! + start,
                        count: windowSize
                    )
                }
            }
            vDSP.multiply(frame, window, result: &frame)

            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                    var splitComplex = DSPSplitComplex(
                        realp: realBuffer.baseAddress!,
                        imagp: imaginaryBuffer.baseAddress!
                    )
                    frame.withUnsafeBytes { rawBuffer in
                        let complexBuffer = rawBuffer.bindMemory(to: DSPComplex.self)
                        vDSP_ctoz(
                            complexBuffer.baseAddress!,
                            2,
                            &splitComplex,
                            1,
                            vDSP_Length(windowSize / 2)
                        )
                    }
                    vDSP_fft_zrip(
                        fftSetup,
                        &splitComplex,
                        1,
                        vDSP_Length(log2(Double(windowSize))),
                        FFTDirection(FFT_FORWARD)
                    )
                    vDSP_zvmags(
                        &splitComplex,
                        1,
                        &magnitudes,
                        1,
                        vDSP_Length(windowSize / 2)
                    )
                }
            }

            bandEnergies.append(bandRanges.map { range in
                var sum: Float = 0
                magnitudes.withUnsafeBufferPointer { buffer in
                    vDSP_sve(
                        buffer.baseAddress! + range.lowerBound,
                        1,
                        &sum,
                        vDSP_Length(range.count)
                    )
                }
                let mean = sum / Float(max(1, range.count))
                return 10 * log10(max(mean, Float.leastNonzeroMagnitude))
            })
        }

        let frameFloors = bandEnergies.map(median)
        return bandEnergies.indices.map { frameIndex in
            let lowerFrame = max(0, frameIndex - rollingMedianRadius)
            let upperFrame = min(frameFloors.count - 1, frameIndex + rollingMedianRadius)
            let rollingFloor = median(Array(frameFloors[lowerFrame...upperFrame]))
            let energies = bandEnergies[frameIndex]

            return energies.indices.compactMap { band -> SpectralPeak? in
                let left = band > 0 ? energies[band - 1] : -.infinity
                let right = band + 1 < energies.count ? energies[band + 1] : -.infinity
                guard energies[band] > rollingFloor + peakFloorDecibels,
                      energies[band] > left,
                      energies[band] >= right
                else {
                    return nil
                }
                return SpectralPeak(band: band, energy: energies[band])
            }
            .sorted {
                if $0.energy != $1.energy {
                    return $0.energy > $1.energy
                }
                return $0.band < $1.band
            }
            .prefix(3)
            .sorted { $0.band < $1.band }
        }
    }

    static func logarithmicBandRanges(sampleRate: Int) -> [Range<Int>] {
        let ratio = highestFrequency / lowestFrequency
        let edges = (0...bandCount).map { index in
            lowestFrequency * pow(ratio, Double(index) / Double(bandCount))
        }
        let maximumBin = windowSize / 2 - 1

        return (0..<bandCount).map { index in
            let lower = max(
                1,
                min(maximumBin, Int(floor(edges[index] * Double(windowSize) / Double(sampleRate))))
            )
            let upper = max(
                lower + 1,
                min(
                    windowSize / 2,
                    Int(ceil(edges[index + 1] * Double(windowSize) / Double(sampleRate)))
                )
            )
            return lower..<upper
        }
    }

    static func makeLandmarks(from peaks: [[SpectralPeak]]) -> [AudioFingerprintLandmark] {
        var landmarks = [AudioFingerprintLandmark]()
        landmarks.reserveCapacity(peaks.count * 24)

        for anchorFrame in peaks.indices {
            guard !peaks[anchorFrame].isEmpty else {
                continue
            }
            for deltaFrame in targetFrameOffsets {
                let targetFrame = anchorFrame + deltaFrame
                guard targetFrame < peaks.count else {
                    continue
                }
                for anchor in peaks[anchorFrame] {
                    for target in peaks[targetFrame] {
                        let energyRelation = quantizedEnergyRelation(
                            target.energy - anchor.energy
                        )
                        let hash =
                            UInt32(anchor.band & 0x1F) << 27 |
                            UInt32(target.band & 0x1F) << 22 |
                            UInt32(deltaFrame & 0x3FF) << 12 |
                            UInt32(energyRelation & 0x0FFF)
                        landmarks.append(AudioFingerprintLandmark(
                            hash: hash,
                            frame: anchorFrame
                        ))
                    }
                }
            }
        }

        return landmarks
    }

    static func quantizedEnergyRelation(_ decibels: Float) -> Int {
        Int(((decibels + 64) / 16).rounded()).clamped(to: 0...0x0FFF)
    }

    static func strongestClusterCenters(
        voteCounts: [Int: Int],
        limit: Int
    ) -> [Int] {
        let ranked = voteCounts.keys.map { center in
            (
                center: center,
                votes: (center - 1...center + 1).reduce(0) {
                    $0 + (voteCounts[$1] ?? 0)
                }
            )
        }.sorted {
            if $0.votes != $1.votes {
                return $0.votes > $1.votes
            }
            return $0.center < $1.center
        }

        var selected = [Int]()
        for entry in ranked where selected.allSatisfy({ abs($0 - entry.center) > 2 }) {
            selected.append(entry.center)
            if selected.count == limit {
                break
            }
        }
        return selected
    }

    static func evaluateCluster(
        center: Int,
        reference: AudioFingerprint,
        candidateFramesByHash: [UInt32: [Int]]
    ) -> EvaluatedCluster {
        var matchedOffsets = [Int]()
        matchedOffsets.reserveCapacity(reference.landmarks.count)

        for referenceLandmark in reference.landmarks {
            guard let candidateFrames = candidateFramesByHash[referenceLandmark.hash] else {
                continue
            }

            var closestOffset: Int?
            for candidateFrame in candidateFrames {
                let offset = candidateFrame - referenceLandmark.frame
                guard abs(offset - center) <= 1 else {
                    continue
                }
                if closestOffset == nil
                    || abs(offset - center) < abs(closestOffset! - center)
                    || (
                        abs(offset - center) == abs(closestOffset! - center)
                            && offset < closestOffset!
                    )
                {
                    closestOffset = offset
                }
            }
            if let closestOffset {
                matchedOffsets.append(closestOffset)
            }
        }

        guard !matchedOffsets.isEmpty else {
            return EvaluatedCluster(
                center: center,
                representativeOffset: center,
                frameSpread: 0,
                uniqueReferenceMatches: 0
            )
        }

        matchedOffsets.sort()
        let meanOffset = Double(matchedOffsets.reduce(0, +))
            / Double(matchedOffsets.count)
        let variance = matchedOffsets.reduce(into: 0.0) {
            let distance = Double($1) - meanOffset
            $0 += distance * distance
        } / Double(matchedOffsets.count)
        return EvaluatedCluster(
            center: center,
            representativeOffset: matchedOffsets[matchedOffsets.count / 2],
            frameSpread: sqrt(variance),
            uniqueReferenceMatches: matchedOffsets.count
        )
    }

    static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else {
            return 0
        }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
