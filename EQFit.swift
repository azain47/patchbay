import Foundation

/// Parametric EQ fitter: given a desired magnitude correction curve, fits a set of biquad filters
/// (peaking + optional low/high shelf) whose summed response approximates it.
///
/// Algorithm overview:
/// 1. Resample the input curve onto a log grid (~240 points, 1/24 octave, 20 Hz–20 kHz).
///    Weights: 1.0 up to 10 kHz, linearly fading to 0.3 at 20 kHz.
/// 2. Greedy initialization: for each band, find the grid point with largest |weighted residual|,
///    place a peaking filter there (or low/high shelf at the edges), and refine all filters for
///    ~40 iterations. Repeat until `bands` reached.
/// 3. Coordinate descent refinement: adjust each filter's (ln fc, gain, ln Q) with numerical
///    central differences, minimizing weighted squared error. Final pass: ~300 iterations or until
///    loss improvement < 1e-4 dB².
/// 4. Postprocess: drop |gain| < 0.2 dB filters, set preamp to prevent clipping, round/sort results.
enum EQFit {
    static func fit(_ curve: [(frequency: Double, gainDB: Double)], bands: Int, sampleRate: Double = 48_000) -> ParametricPreset {
        let gridFreqs = logGrid(20, 20_000, 240)
        let gridWeights = gridWeights(gridFreqs)
        
        // Resample input curve to log grid
        var desired = [Double]()
        for freq in gridFreqs {
            desired.append(interpolateCurve(curve, freq))
        }
        
        // Initialize filters greedily
        var filters: [FilterState] = []
        var sum = [Double](repeating: 0, count: gridFreqs.count)
        var rows: [[Double]] = []
        
        for _ in 0..<bands {
            let residual = zip(desired, sum).map { $0 - $1 }
            // Filters are seated below 12 kHz; the loss still keeps the top octave in check.
            let weighted = gridFreqs.indices.map { gridFreqs[$0] <= 12_000 ? residual[$0] * gridWeights[$0] : 0 }
            
            guard let (peakIdx, peakValue) = weighted.enumerated().max(by: { abs($0.element) < abs($1.element) }) else { break }
            if abs(peakValue) < 0.01 { break }
            
            let peakFreq = gridFreqs[peakIdx]
            let peakGain = residual[peakIdx]
            
            // Find Q from bump width
            let halfPeak = abs(peakGain) / 2
            var leftIdx = peakIdx
            while leftIdx > 0 && abs(residual[leftIdx - 1]) > halfPeak { leftIdx -= 1 }
            var rightIdx = peakIdx
            while rightIdx < gridFreqs.count - 1 && abs(residual[rightIdx + 1]) > halfPeak { rightIdx += 1 }
            

            var q = peakFreq / (gridFreqs[rightIdx] - gridFreqs[leftIdx])
            q = max(0.3, min(10, q))
            
            // Determine filter type
            var type: FilterType = .peaking
            let isLowBump = peakFreq < 120 && (leftIdx == 0 || abs(residual[0]) >= halfPeak)
            let isHighBump = peakFreq > 6000 && (rightIdx == gridFreqs.count - 1 || abs(residual[gridFreqs.count - 1]) >= halfPeak)
            
            if isLowBump && filters.first(where: { $0.type == .lowShelf }) == nil {
                type = .lowShelf
                q = 0.707
            } else if isHighBump && filters.first(where: { $0.type == .highShelf }) == nil {
                type = .highShelf
                q = 0.707
            }
            
            let newFilter = FilterState(type: type, frequency: peakFreq, gainDB: peakGain, q: q)
            filters.append(newFilter)
            
            // Update response cache
            let newRow = computeFilterResponse(newFilter, gridFreqs: gridFreqs, sampleRate: sampleRate)
            rows.append(newRow)
            
            sum = zip(sum, newRow).map { $0 + $1 }
            
            // Refine all filters so far
            refineFilters(&filters, &rows, &sum, desired: desired, weights: gridWeights, gridFreqs: gridFreqs, sampleRate: sampleRate, maxIterations: 40)
        }
        
        // Final refinement
        if !filters.isEmpty {
            refineFilters(&filters, &rows, &sum, desired: desired, weights: gridWeights, gridFreqs: gridFreqs, sampleRate: sampleRate, maxIterations: 300, earlyStop: true)
        }
        
        // Postprocess
        var bands = filters.filter { abs($0.gainDB) >= 0.2 }.map { filter -> EQBand in
            EQBand(
                type: filter.type,
                frequency: roundSigFigs(filter.frequency, 3),
                gainDB: (filter.gainDB * 10).rounded() / 10,
                q: (filter.q * 100).rounded() / 100,
                enabled: true
            )
        }
        bands.sort { $0.frequency < $1.frequency }
        
        // Compute preamp
        let finalSum = computeSum(rows, gridFreqs: gridFreqs, sampleRate: sampleRate)
        var preamp = 0.0
        if let maxResponse = finalSum.max(), maxResponse > 0 {
            preamp = -(maxResponse * 10).rounded() / 10
        }
        
        return ParametricPreset(preampDB: preamp, bands: bands)
    }
    
    // MARK: - Helpers
    
    private struct FilterState {
        var type: FilterType
        var frequency: Double
        var gainDB: Double
        var q: Double
    }
    
    private static func logGrid(_ f0: Double, _ f1: Double, _ count: Int) -> [Double] {
        let octaves = log2(f1 / f0)
        return (0..<count).map { i in
            f0 * pow(2, octaves * Double(i) / Double(count - 1))
        }
    }
    
    /// Full weight to 10 kHz, fading to a tenth by 14 kHz: measurements above that are
    /// rig- and seat-dependent, and a filter parked there is a filter wasted.
    private static func gridWeights(_ freqs: [Double]) -> [Double] {
        freqs.map { f in f <= 10_000 ? 1.0 : max(0.1, 1 - log2(f / 10_000) / log2(1.4)) }
    }
    
    private static func interpolateCurve(_ curve: [(frequency: Double, gainDB: Double)], _ freq: Double) -> Double {
        guard !curve.isEmpty else { return 0 }
        if freq <= curve.first!.frequency { return curve.first!.gainDB }
        if freq >= curve.last!.frequency { return curve.last!.gainDB }
        
        for i in 0..<curve.count - 1 {
            let f0 = curve[i].frequency
            let f1 = curve[i + 1].frequency
            if freq >= f0 && freq <= f1 {
                let g0 = curve[i].gainDB
                let g1 = curve[i + 1].gainDB
                let t = log(freq / f0) / log(f1 / f0)
                return g0 + t * (g1 - g0)
            }
        }
        return curve.last!.gainDB
    }
    
    private static func computeFilterResponse(_ filter: FilterState, gridFreqs: [Double], sampleRate: Double) -> [Double] {
        let coeffs = BiquadDesign.coefficients(
            type: filter.type,
            frequency: filter.frequency,
            gainDB: filter.gainDB,
            q: filter.q,
            sampleRate: sampleRate
        )
        
        return gridFreqs.map { freq in
            responseMagnitudeDB(coeffs, freq: freq, sampleRate: sampleRate)
        }
    }
    
    private static func responseMagnitudeDB(_ coeff: PBBiquad, freq: Double, sampleRate: Double) -> Double {
        let w = 2 * Double.pi * freq / sampleRate
        let c1 = cos(w), s1 = sin(w)
        let c2 = cos(2 * w), s2 = sin(2 * w)
        
        let nr = coeff.b0 + coeff.b1 * c1 + coeff.b2 * c2
        let ni = -(coeff.b1 * s1 + coeff.b2 * s2)
        let dr = 1 + coeff.a1 * c1 + coeff.a2 * c2
        let di = -(coeff.a1 * s1 + coeff.a2 * s2)
        
        let nMag = sqrt(max(1e-40, nr * nr + ni * ni))
        let dMag = sqrt(max(1e-40, dr * dr + di * di))
        
        return max(-120, 20 * log10(max(1e-40, nMag / dMag)))
    }
    
    private static func computeSum(_ rows: [[Double]], gridFreqs: [Double], sampleRate: Double) -> [Double] {
        guard !rows.isEmpty else { return [Double](repeating: 0, count: gridFreqs.count) }
        var sum = rows[0]
        for i in 1..<rows.count {
            for k in 0..<sum.count {
                sum[k] += rows[i][k]
            }
        }
        return sum
    }
    
    private static func refineFilters(
        _ filters: inout [FilterState],
        _ rows: inout [[Double]],
        _ sum: inout [Double],
        desired: [Double],
        weights: [Double],
        gridFreqs: [Double],
        sampleRate: Double,
        maxIterations: Int,
        earlyStop: Bool = false
    ) {
        let eps = 1e-6
        let stepSizes = (fc: 0.02, gain: 0.1, q: 0.02)
        var prevLoss = Double.infinity
        var noImprovementCount = 0
        
        for iteration in 0..<maxIterations {
            var totalGradient = 0.0
            
            for filterIdx in 0..<filters.count {
                // Gradient w.r.t. ln(fc)
                let fcDelta = filters[filterIdx].frequency * eps
                var loss1 = 0.0, loss2 = 0.0
                
                filters[filterIdx].frequency += fcDelta
                let row1 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                var tempSum = sum
                for k in 0..<tempSum.count {
                    tempSum[k] = tempSum[k] - rows[filterIdx][k] + row1[k]
                }
                loss1 = weightedError(tempSum, desired: desired, weights: weights)
                
                filters[filterIdx].frequency -= 2 * fcDelta
                let row0 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                tempSum = sum
                for k in 0..<tempSum.count {
                    tempSum[k] = tempSum[k] - rows[filterIdx][k] + row0[k]
                }
                loss2 = weightedError(tempSum, desired: desired, weights: weights)
                
                filters[filterIdx].frequency += fcDelta // restore
                let gradFc = (loss1 - loss2) / (2 * fcDelta)
                filters[filterIdx].frequency -= gradFc * stepSizes.fc * filters[filterIdx].frequency
                filters[filterIdx].frequency = max(20, min(20_000, filters[filterIdx].frequency))
                
                // Gradient w.r.t. gain
                filters[filterIdx].gainDB += stepSizes.gain / 2
                let rowGain1 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                tempSum = sum
                for k in 0..<tempSum.count {
                    tempSum[k] = tempSum[k] - rows[filterIdx][k] + rowGain1[k]
                }
                loss1 = weightedError(tempSum, desired: desired, weights: weights)
                
                filters[filterIdx].gainDB -= stepSizes.gain
                let rowGain0 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                tempSum = sum
                for k in 0..<tempSum.count {
                    tempSum[k] = tempSum[k] - rows[filterIdx][k] + rowGain0[k]
                }
                loss2 = weightedError(tempSum, desired: desired, weights: weights)
                
                filters[filterIdx].gainDB += stepSizes.gain / 2 // restore
                let gradGain = (loss1 - loss2) / stepSizes.gain
                filters[filterIdx].gainDB -= gradGain * stepSizes.gain
                filters[filterIdx].gainDB = max(-20, min(20, filters[filterIdx].gainDB))
                
                // Gradient w.r.t. ln(Q) (only for peaking, skip for shelves)
                if filters[filterIdx].type == .peaking {
                    let qDelta = filters[filterIdx].q * eps
                    filters[filterIdx].q += qDelta
                    let rowQ1 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                    tempSum = sum
                    for k in 0..<tempSum.count {
                        tempSum[k] = tempSum[k] - rows[filterIdx][k] + rowQ1[k]
                    }
                    loss1 = weightedError(tempSum, desired: desired, weights: weights)
                    
                    filters[filterIdx].q -= 2 * qDelta
                    let rowQ0 = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
                    tempSum = sum
                    for k in 0..<tempSum.count {
                        tempSum[k] = tempSum[k] - rows[filterIdx][k] + rowQ0[k]
                    }
                    loss2 = weightedError(tempSum, desired: desired, weights: weights)
                    
                    filters[filterIdx].q += qDelta // restore
                    let gradQ = (loss1 - loss2) / (2 * qDelta)
                    filters[filterIdx].q -= gradQ * stepSizes.q * filters[filterIdx].q
                    filters[filterIdx].q = max(0.3, min(12, filters[filterIdx].q))
                }
                
                // Update row and sum
                rows[filterIdx] = computeFilterResponse(filters[filterIdx], gridFreqs: gridFreqs, sampleRate: sampleRate)
            }
            
            sum = computeSum(rows, gridFreqs: gridFreqs, sampleRate: sampleRate)
            let loss = weightedError(sum, desired: desired, weights: weights)
            totalGradient = abs(loss - prevLoss)
            
            if earlyStop && totalGradient < 1e-4 {
                noImprovementCount += 1
                if noImprovementCount > 20 { break }
            }
            
            prevLoss = loss
        }
    }
    
    private static func weightedError(_ measured: [Double], desired: [Double], weights: [Double]) -> Double {
        var sumErr = 0.0
        var sumWeights = 0.0
        for i in 0..<measured.count {
            let err = measured[i] - desired[i]
            sumErr += weights[i] * err * err
            sumWeights += weights[i]
        }
        return sumWeights > 0 ? sumErr / sumWeights : 0
    }
    
    private static func roundSigFigs(_ value: Double, _ sigFigs: Int) -> Double {
        guard value != 0 else { return 0 }
        let exponent = floor(log10(abs(value)))
        let scale = pow(10, Double(sigFigs - 1) - exponent)
        return (value * scale).rounded() / scale
    }
}
