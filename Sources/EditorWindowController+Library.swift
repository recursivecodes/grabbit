import AppKit

// MARK: - Library management extension for EditorWindowController
//
// Handles the thumbnail strip, multi-document switching, and library persistence.
// Sync-to-document helpers (rewireOverlayState, syncSidebarToDocument, etc.) live
// in EditorWindowController.swift to keep access to private ivars.

extension EditorWindowController {

    // MARK: - Bootstrap

    /// Populates the strip from existing library images. For each PNG that has a
    /// .grabbit sidecar, annotations are restored and the thumbnail reflects them.
    /// loadEntries returns newest→oldest so appending produces newest-on-left order.
    func loadExistingLibraryItems(excluding excluded: Set<URL> = []) {
        let entries = LibraryManager.shared.loadEntries(excluding: excluded)
        for entry in entries {
            guard let img = NSImage(contentsOf: entry.libraryURL) else { continue }
            let doc = GrabbitDocument(image: img)

            // Restore annotations from sidecar if one exists.
            if let data = LibraryManager.shared.loadSidecar(for: entry.libraryURL) {
                doc.applyAnnotations(data)
            }

            // Use a rendered composite for the thumbnail when annotations are present.
            var updatedEntry = entry
            let hasAnnotations = doc.arrows.count + doc.textAnnotations.count +
                doc.shapes.count + doc.blurRegions.count + doc.highlights.count +
                doc.spotlights.count + doc.stepBadges.count > 0
            if hasAnnotations {
                let rendered = doc.rendered()
                updatedEntry.thumbnailImage = LibraryManager.shared.makeThumbnail(rendered)
            }

            addEntryToStrip(document: doc, entry: updatedEntry, prepend: false)
        }
    }

    /// Adds a new capture (already saved to disk) to the left of the strip and switches to it.
    func addLibraryEntry(document: GrabbitDocument,
                         libraryURL: URL?,
                         capturedAt: Date = Date()) {
        let thumb = LibraryManager.shared.makeThumbnail(document.currentImage)
        let url   = libraryURL
                 ?? LibraryManager.shared.libraryURL
                       .appendingPathComponent(UUID().uuidString + ".png")
        let entry = LibraryEntry(id: UUID(), libraryURL: url,
                                 capturedAt: capturedAt, thumbnailImage: thumb)

        // Bump the current index since we're prepending at position 0.
        if currentLibraryIndex >= 0 { currentLibraryIndex += 1 }

        addEntryToStrip(document: document, entry: entry, prepend: true)
        switchToEntry(at: 0)
        scrollThumbStripToStart()
    }

    // MARK: - Switching

    func switchToEntry(at index: Int) {
        guard index >= 0, index < libraryDocuments.count else { return }

        // Save magnification before stashing so we can restore it after the switch.
        let savedMagnification: CGFloat? = currentLibraryIndex >= 0
            ? zoomScroll.magnification : nil

        if currentLibraryIndex >= 0, currentLibraryIndex != index {
            stashCurrentEntry()
        }

        let incoming = libraryDocuments[index]

        // Nil callbacks on the outgoing document.
        if currentLibraryIndex >= 0,
           currentLibraryIndex < libraryDocuments.count,
           libraryDocuments[currentLibraryIndex] !== incoming {
            let outgoing = libraryDocuments[currentLibraryIndex]
            outgoing.onAnnotationsChanged = nil
            outgoing.onImageChanged       = nil
        }

        // Wire callbacks on the incoming document.
        incoming.onAnnotationsChanged = { [weak self] in
            self?.annotationOverlay.needsDisplay = true
        }
        incoming.onImageChanged = { [weak self] in
            guard let self else { return }
            self.captureView.image = self.grabbitDocument.currentImage
            self.refreshBaseImage()
            self.refreshShadow()
            self.annotationOverlay.needsDisplay = true
            if self.grabbitDocument.hasImage { self.applyActiveState() }
        }

        currentLibraryIndex        = index
        grabbitDocument            = incoming
        annotationOverlay.document = incoming

        // Cleanly exit any active tool.
        if !cropOverlay.isHidden { deactivateCropToolForSwitch() }
        annotationOverlay.finalizeEditing()
        syncToolbarStateForSwitch()

        // Sync overlay draw state and sidebar controls to the new document.
        rewireOverlayState(from: incoming)
        syncSidebarToDocument(incoming)

        updateThumbSelection(selectedIndex: index)

        refreshBaseImage()
        refreshShadow()
        if incoming.hasImage { applyActiveState() } else { applyEmptyState() }

        // Retain zoom level if switching from an existing entry; otherwise fit.
        hasAppliedInitialZoom = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let zoom = savedMagnification, zoom > 0.01 {
                self.zoomScroll.magnification = zoom
                self.hasAppliedInitialZoom = true
                self.updateZoomLabel()
            } else {
                self.applyFitZoom()
            }
        }
    }

    // MARK: - Stash (lazy save on switch / Cmd+S)
    //
    // Writes the annotation sidecar (.grabbit JSON) for the current entry.
    // The base PNG is never modified — it always holds the original screenshot.
    // The thumbnail cell is updated in memory from the rendered composite.

    func stashCurrentEntry() {
        guard currentLibraryIndex >= 0,
              currentLibraryIndex < libraryDocuments.count,
              currentLibraryIndex < libraryEntries.count else { return }

        annotationOverlay.finalizeEditing()
        let stashedIndex = currentLibraryIndex
        let doc   = libraryDocuments[stashedIndex]
        let entry = libraryEntries[stashedIndex]
        let dispW = captureView.bounds.width

        // Capture everything needed on the main thread before dispatching.
        // CGImage is immutable and thread-safe; NSImage is not, so extract it here.
        let rendered    = doc.rendered(displayWidth: dispW)
        let renderedCG  = rendered.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let renderedSize = rendered.size
        let docData     = doc.encodeAnnotations()

        DispatchQueue.global(qos: .background).async { [weak self] in
            LibraryManager.shared.updateSidecar(for: entry.libraryURL, data: docData)
            let thumb = renderedCG.map {
                LibraryManager.shared.makeThumbnailCG($0, originalSize: renderedSize)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      stashedIndex < self.libraryEntries.count,
                      stashedIndex < self.thumbCells.count else { return }
                if let thumb {
                    self.libraryEntries[stashedIndex].thumbnailImage = thumb
                    self.thumbCells[stashedIndex].thumbnail = thumb
                }
            }
        }
    }

    // MARK: - Strip helpers

    func addEntryToStrip(document: GrabbitDocument, entry: LibraryEntry, prepend: Bool) {
        let footerH = thumbStripHeightConstraint?.constant ?? 110
        let cell = LibraryThumbCell(index: 0, entry: entry, footerHeight: footerH)

        // Dynamic index lookup so prepend / reordering never breaks selection.
        cell.onSelect = { [weak self, weak cell] in
            guard let self, let cell,
                  let idx = self.thumbCells.firstIndex(where: { $0 === cell }) else { return }
            self.switchToEntry(at: idx)
        }
        cell.onDuplicate = { [weak self, weak cell] in
            guard let self, let cell,
                  let idx = self.thumbCells.firstIndex(where: { $0 === cell }) else { return }
            self.duplicateEntry(at: idx)
        }
        cell.onDelete = { [weak self, weak cell] in
            guard let self, let cell,
                  let idx = self.thumbCells.firstIndex(where: { $0 === cell }) else { return }
            self.deleteEntry(at: idx)
        }
        cell.onRevealInFinder = { [weak self, weak cell] in
            guard let self, let cell,
                  let idx = self.thumbCells.firstIndex(where: { $0 === cell }) else { return }
            NSWorkspace.shared.activateFileViewerSelecting([self.libraryEntries[idx].libraryURL])
        }

        if prepend {
            libraryDocuments.insert(document, at: 0)
            libraryEntries.insert(entry, at: 0)
            thumbCells.insert(cell, at: 0)
            thumbStack.insertArrangedSubview(cell, at: 0)
        } else {
            libraryDocuments.append(document)
            libraryEntries.append(entry)
            thumbCells.append(cell)
            thumbStack.addArrangedSubview(cell)
        }
    }

    func updateThumbSelection(selectedIndex: Int) {
        for (i, cell) in thumbCells.enumerated() {
            cell.isSelected = (i == selectedIndex)
        }
    }

    func scrollThumbStripToStart() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let first = self.thumbCells.first else { return }
            let frame = first.convert(first.bounds, to: self.thumbScroll.contentView)
            self.thumbScroll.contentView.scrollToVisible(frame)
        }
    }

    func scrollThumbStripToEnd() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let last = self.thumbCells.last else { return }
            let frame = last.convert(last.bounds, to: self.thumbScroll.contentView)
            self.thumbScroll.contentView.scrollToVisible(frame)
        }
    }

    // MARK: - Context menu actions

    func duplicateEntry(at index: Int) {
        guard index >= 0,
              index < libraryDocuments.count,
              index < libraryEntries.count else { return }

        if index == currentLibraryIndex { annotationOverlay.finalizeEditing() }

        let doc     = libraryDocuments[index]
        let docData = doc.encodeAnnotations(capturedAt: Date())

        // CGImage is immutable and thread-safe. Wrapping it in a new NSImage gives the
        // background thread its own object that doesn't share state with the displayed image.
        let src = doc.currentImage
        guard let cgImg = src.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let baseImage = NSImage(cgImage: cgImg, size: src.size)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let newURL = LibraryManager.shared.saveCapture(baseImage) else { return }
            LibraryManager.shared.updateSidecar(for: newURL, data: docData)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let newDoc = GrabbitDocument(image: baseImage)
                newDoc.applyAnnotations(docData)
                self.addLibraryEntry(document: newDoc, libraryURL: newURL, capturedAt: Date())
            }
        }
    }

    func deleteEntry(at index: Int) {
        guard index >= 0,
              index < libraryDocuments.count,
              index < libraryEntries.count,
              index < thumbCells.count else { return }

        let alert = NSAlert()
        alert.messageText = "Delete this image?"
        alert.informativeText = libraryDocuments[index].isDirty
            ? "This image has unsaved annotations. They will be permanently lost."
            : "The file will be removed from the library and deleted from disk."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let entry = libraryEntries[index]
        let cell  = thumbCells[index]

        DispatchQueue.global(qos: .background).async {
            try? FileManager.default.removeItem(at: entry.libraryURL)
            // Also remove the annotation sidecar if one exists.
            let sidecarURL = LibraryManager.shared.sidecarURL(for: entry.libraryURL)
            try? FileManager.default.removeItem(at: sidecarURL)
        }

        thumbStack.removeArrangedSubview(cell)
        cell.removeFromSuperview()

        libraryDocuments.remove(at: index)
        libraryEntries.remove(at: index)
        thumbCells.remove(at: index)

        if libraryDocuments.isEmpty {
            currentLibraryIndex = -1
            applyEmptyState()
        } else if index == currentLibraryIndex {
            // Deleted the active entry; switch to the nearest remaining one.
            currentLibraryIndex = -1
            switchToEntry(at: min(index, libraryDocuments.count - 1))
        } else if index < currentLibraryIndex {
            currentLibraryIndex -= 1
            updateThumbSelection(selectedIndex: currentLibraryIndex)
        } else {
            updateThumbSelection(selectedIndex: currentLibraryIndex)
        }
    }
}
