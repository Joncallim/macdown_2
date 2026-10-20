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
            let payload = try await PreviewResourceAdmission.shared.read(reference, in: context)
            guard !context.isRevoked, !Task.isCancelled else { throw PreviewResourceAdmissionError.revoked }
            return PreviewImageBytes(data: payload.snapshot.bytes, reservation: payload)
        }, isLive: { !context.isRevoked })
    }
}
