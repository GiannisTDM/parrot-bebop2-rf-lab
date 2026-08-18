import AppKit
import AVFoundation
import CoreMedia

final class H264VideoView: NSView {
    private let displayLayer = AVSampleBufferDisplayLayer()
    private var formatDescription: CMVideoFormatDescription?
    private var sps: Data?
    private var pps: Data?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        displayLayer.videoGravity = .resizeAspect
        displayLayer.backgroundColor = NSColor.black.cgColor
        layer?.addSublayer(displayLayer)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        displayLayer.frame = bounds
    }

    func display(nalUnits: [Data]) {
        for nalu in nalUnits {
            guard let byte = nalu.first else { continue }
            switch byte & 0x1f {
            case 7: sps = nalu
            case 8: pps = nalu
            default: break
            }
        }
        if formatDescription == nil { rebuildFormatDescription() }
        guard let formatDescription else { return }

        let frameNALs = nalUnits.filter {
            guard let byte = $0.first else { return false }
            return ![7, 8, 9].contains(Int(byte & 0x1f))
        }
        guard !frameNALs.isEmpty else { return }

        var sampleData = Data()
        for nalu in frameNALs {
            var size = UInt32(nalu.count).bigEndian
            withUnsafeBytes(of: &size) { sampleData.append(contentsOf: $0) }
            sampleData.append(nalu)
        }

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: sampleData.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: sampleData.count,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else { return }
        let replaceStatus = sampleData.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(
                with: bytes.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: sampleData.count
            )
        }
        guard replaceStatus == kCMBlockBufferNoErr else { return }

        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: .invalid,
            decodeTimeStamp: .invalid
        )
        var sampleSize = sampleData.count
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else { return }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true),
           let first = (attachments as NSArray).firstObject as? NSMutableDictionary {
            first[kCMSampleAttachmentKey_DisplayImmediately] = true
        }

        if displayLayer.status == .failed { displayLayer.flush() }
        displayLayer.enqueue(sampleBuffer)
    }

    func reset() {
        displayLayer.flushAndRemoveImage()
        formatDescription = nil
        sps = nil
        pps = nil
    }

    private func rebuildFormatDescription() {
        guard let sps, let pps else { return }
        var description: CMFormatDescription?
        let status = sps.withUnsafeBytes { spsBytes in
            pps.withUnsafeBytes { ppsBytes in
                let pointers: [UnsafePointer<UInt8>] = [
                    spsBytes.bindMemory(to: UInt8.self).baseAddress!,
                    ppsBytes.bindMemory(to: UInt8.self).baseAddress!
                ]
                let sizes = [sps.count, pps.count]
                return pointers.withUnsafeBufferPointer { pointerBuffer in
                    sizes.withUnsafeBufferPointer { sizeBuffer in
                        CMVideoFormatDescriptionCreateFromH264ParameterSets(
                            allocator: kCFAllocatorDefault,
                            parameterSetCount: 2,
                            parameterSetPointers: pointerBuffer.baseAddress!,
                            parameterSetSizes: sizeBuffer.baseAddress!,
                            nalUnitHeaderLength: 4,
                            formatDescriptionOut: &description
                        )
                    }
                }
            }
        }
        if status == noErr { formatDescription = description }
    }
}
