import Foundation
import LocalResourceAccess
import Preview

/// Supplies Textual only the bytes admitted for this immutable load. URL parsing is lexical and happens before any
/// filesystem access; an absolute, remote or authority-bearing URL cannot borrow the document's folder grant.
enum PreviewResourceImageProvider {
    static func loader(for context: PreviewResourceLoad?) -> PreviewResourceImageLoader {
        guard let context else { return PreviewResourceImageLoader() }
        return PreviewResourceImageLoader(provider: { url in
            guard !context.isRevoked, !Task.isCancelled else { throw PreviewResourceAdmissionError.revoked }
            let authored = url.relativeString
            guard let components = URLComponents(string: authored),
                  components.scheme == nil, components.host == nil,
                  components.user == nil, components.password == nil, components.port == nil
            else { throw ResourceReadError.invalidReference }
            let reference = try ResourceReference.parse(authored)
            let payload = try await readImage(reference, in: context)
            guard !context.isRevoked, !Task.isCancelled else { throw PreviewResourceAdmissionError.revoked }
            return PreviewImageBytes(data: payload.snapshot.bytes, reservation: payload)
        }, isLive: { !context.isRevoked }, decodeBudget: context.imageDecodeBudget)
    }

    /// Textual does not retry failed attachments. A burst can temporarily occupy every input reservation even
    /// for tiny images. Allow seven 25 ms retry delays for this same load; every attempt is fully admitted.
    static func readImage(
        _ reference: ResourceReference, in context: PreviewResourceLoad,
        admission: PreviewResourceAdmission = .shared
    ) async throws -> PreviewResourcePayload {
        for attempt in 0 ..< 8 {
            try Task.checkCancellation()
            guard !context.isRevoked else { throw PreviewResourceAdmissionError.revoked }
            do {
                return try await admission.read(reference, in: context)
            } catch PreviewResourceAdmissionError.limitExceeded {
                guard attempt < 7, let status = await admission.status(for: context),
                      status.reserved > 0,
                      status.delivered <= PreviewResourceAdmission.loadLimit - PreviewResourceAdmission.resourceLimit,
                      status.reserved > PreviewResourceAdmission.loadLimit
                      - PreviewResourceAdmission.resourceLimit - status.delivered
                else { throw PreviewResourceAdmissionError.limitExceeded }
                try await Task.sleep(for: .milliseconds(25))
            }
        }
        throw PreviewResourceAdmissionError.limitExceeded
    }
}
