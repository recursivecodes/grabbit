import AppKit

// MARK: - TabbedEditorSidebar

class TabbedEditorSidebar: NSView {
    private let tabControl:       NSSegmentedControl
    private let propertiesScroll: NSScrollView
    private let effectsScroll:    NSScrollView
    private let effectsStack:     NSStackView
    private let propertiesStack:  NSStackView
    private var noToolView:       NSView!
    private var arrowPropViews:   [NSView] = []
    private var textPropViews:    [NSView] = []
    private var shapePropViews:   [NSView] = []

    init(
        arrowWeightSlider: NSSlider, arrowWeightLabel: NSTextField, arrowColorWell: NSColorWell,
        textFontPopup: NSPopUpButton,
        textFontSizeSlider: NSSlider, textFontSizeLabel: NSTextField,
        textFontColorWell: NSColorWell,
        textOutlineColorWell: NSColorWell,
        textOutlineWeightSlider: NSSlider, textOutlineWeightLabel: NSTextField,
        shapeTypePopup: NSPopUpButton,
        shapeBorderWeightSlider: NSSlider, shapeBorderWeightLabel: NSTextField,
        shapeBorderColorWell: NSColorWell,
        shapeFillColorWell: NSColorWell
    ) {
        tabControl = NSSegmentedControl(
            labels: ["Properties", "Effects"],
            trackingMode: .selectOne, target: nil, action: nil
        )
        tabControl.selectedSegment = 0
        tabControl.controlSize = .small
        tabControl.translatesAutoresizingMaskIntoConstraints = false

        effectsStack = NSStackView()
        effectsStack.orientation = .vertical
        effectsStack.alignment = .left
        effectsStack.spacing = 0
        effectsStack.translatesAutoresizingMaskIntoConstraints = false

        propertiesStack = NSStackView()
        propertiesStack.orientation = .vertical
        propertiesStack.alignment = .left
        propertiesStack.spacing = 0
        propertiesStack.translatesAutoresizingMaskIntoConstraints = false

        let ps = NSScrollView()
        ps.hasVerticalScroller = true; ps.autohidesScrollers = true
        ps.drawsBackground = false
        ps.translatesAutoresizingMaskIntoConstraints = false
        let pClip = FlippedClipView()
        pClip.drawsBackground = false
        ps.contentView = pClip
        ps.documentView = propertiesStack
        propertiesScroll = ps

        let es = NSScrollView()
        es.hasVerticalScroller = true; es.autohidesScrollers = true
        es.drawsBackground = false
        es.translatesAutoresizingMaskIntoConstraints = false
        let eClip = FlippedClipView()
        eClip.drawsBackground = false
        es.contentView = eClip
        es.documentView = effectsStack
        effectsScroll = es

        super.init(frame: .zero)

        wantsLayer = true
        layer?.backgroundColor = NSColor(calibratedWhite: 0.97, alpha: 1).cgColor

        let sep = NSBox()
        sep.boxType = .custom
        sep.borderWidth = 0
        sep.fillColor = NSColor.separatorColor
        sep.cornerRadius = 0
        sep.translatesAutoresizingMaskIntoConstraints = false

        let tabDivider = NSBox()
        tabDivider.boxType = .separator
        tabDivider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(sep)
        addSubview(tabControl)
        addSubview(tabDivider)
        addSubview(propertiesScroll)
        addSubview(effectsScroll)

        NSLayoutConstraint.activate([
            sep.topAnchor.constraint(equalTo: topAnchor),
            sep.bottomAnchor.constraint(equalTo: bottomAnchor),
            sep.leadingAnchor.constraint(equalTo: leadingAnchor),
            sep.widthAnchor.constraint(equalToConstant: 1),

            tabControl.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            tabControl.leadingAnchor.constraint(equalTo: sep.trailingAnchor, constant: 10),
            tabControl.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            tabDivider.topAnchor.constraint(equalTo: tabControl.bottomAnchor, constant: 8),
            tabDivider.heightAnchor.constraint(equalToConstant: 1),
            tabDivider.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            tabDivider.trailingAnchor.constraint(equalTo: trailingAnchor),

            propertiesScroll.topAnchor.constraint(equalTo: tabDivider.bottomAnchor),
            propertiesScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            propertiesScroll.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            propertiesScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            effectsScroll.topAnchor.constraint(equalTo: tabDivider.bottomAnchor),
            effectsScroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            effectsScroll.leadingAnchor.constraint(equalTo: sep.trailingAnchor),
            effectsScroll.trailingAnchor.constraint(equalTo: trailingAnchor),

            propertiesStack.topAnchor.constraint(equalTo: pClip.topAnchor),
            propertiesStack.leadingAnchor.constraint(equalTo: pClip.leadingAnchor),
            propertiesStack.widthAnchor.constraint(equalTo: pClip.widthAnchor),
            effectsStack.topAnchor.constraint(equalTo: eClip.topAnchor),
            effectsStack.leadingAnchor.constraint(equalTo: eClip.leadingAnchor),
            effectsStack.widthAnchor.constraint(equalTo: eClip.widthAnchor),
        ])

        // ── Properties: "no tool" placeholder ───────────────────────────────────
        let placeholder = NSTextField(labelWithString: "Select a tool from the\ntoolbar to see its properties.")
        placeholder.font = NSFont.systemFont(ofSize: 12)
        placeholder.textColor = .secondaryLabelColor
        placeholder.alignment = .center
        placeholder.lineBreakMode = .byWordWrapping
        placeholder.maximumNumberOfLines = 0
        placeholder.translatesAutoresizingMaskIntoConstraints = false

        let ntBox = NSView()
        ntBox.translatesAutoresizingMaskIntoConstraints = false
        ntBox.addSubview(placeholder)
        NSLayoutConstraint.activate([
            placeholder.topAnchor.constraint(equalTo: ntBox.topAnchor, constant: 24),
            placeholder.bottomAnchor.constraint(equalTo: ntBox.bottomAnchor, constant: -24),
            placeholder.leadingAnchor.constraint(equalTo: ntBox.leadingAnchor, constant: 14),
            placeholder.trailingAnchor.constraint(equalTo: ntBox.trailingAnchor, constant: -14),
        ])
        propertiesStack.addArrangedSubview(ntBox)
        noToolView = ntBox

        // ── Properties: arrow tool section ──────────────────────────────────────
        let arrowHeader = makeSectionBox("ARROW")
        arrowHeader.isHidden = true
        propertiesStack.addArrangedSubview(arrowHeader)
        arrowPropViews.append(arrowHeader)

        let awRow = makeSidebarRow("Weight", arrowWeightSlider, arrowWeightLabel)
        awRow.isHidden = true
        propertiesStack.addArrangedSubview(awRow)
        arrowPropViews.append(awRow)

        let acRow = makeSidebarRow("Color", arrowColorWell)
        acRow.isHidden = true
        propertiesStack.addArrangedSubview(acRow)
        arrowPropViews.append(acRow)

        // ── Properties: text tool section ───────────────────────────────────────
        let textHeader = makeSectionBox("TEXT")
        textHeader.isHidden = true
        propertiesStack.addArrangedSubview(textHeader)
        textPropViews.append(textHeader)

        let tfFontRow = makeSidebarRow("Font", textFontPopup)
        tfFontRow.isHidden = true
        propertiesStack.addArrangedSubview(tfFontRow)
        textPropViews.append(tfFontRow)

        let tfSizeRow = makeSidebarRow("Size", textFontSizeSlider, textFontSizeLabel)
        tfSizeRow.isHidden = true
        propertiesStack.addArrangedSubview(tfSizeRow)
        textPropViews.append(tfSizeRow)

        let tfColorRow = makeSidebarRow("Color", textFontColorWell)
        tfColorRow.isHidden = true
        propertiesStack.addArrangedSubview(tfColorRow)
        textPropViews.append(tfColorRow)

        let toColorRow = makeSidebarRow("Outline", textOutlineColorWell)
        toColorRow.isHidden = true
        propertiesStack.addArrangedSubview(toColorRow)
        textPropViews.append(toColorRow)

        let toWtRow = makeSidebarRow("Thickness", textOutlineWeightSlider, textOutlineWeightLabel)
        toWtRow.isHidden = true
        propertiesStack.addArrangedSubview(toWtRow)
        textPropViews.append(toWtRow)

        // ── Properties: shape tool section ──────────────────────────────────────
        let shapeHeader = makeSectionBox("SHAPE")
        shapeHeader.isHidden = true
        propertiesStack.addArrangedSubview(shapeHeader)
        shapePropViews.append(shapeHeader)

        let shapeTypeRow = makeSidebarRow("Type", shapeTypePopup)
        shapeTypeRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeTypeRow)
        shapePropViews.append(shapeTypeRow)

        let shapeBorderRow = makeSidebarRow("Border", shapeBorderWeightSlider, shapeBorderWeightLabel)
        shapeBorderRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeBorderRow)
        shapePropViews.append(shapeBorderRow)

        let shapeBorderColorRow = makeSidebarRow("Color", shapeBorderColorWell)
        shapeBorderColorRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeBorderColorRow)
        shapePropViews.append(shapeBorderColorRow)

        let shapeFillColorRow = makeSidebarRow("Fill", shapeFillColorWell)
        shapeFillColorRow.isHidden = true
        propertiesStack.addArrangedSubview(shapeFillColorRow)
        shapePropViews.append(shapeFillColorRow)

        // Start showing Properties tab
        effectsScroll.isHidden = true

        tabControl.target = self
        tabControl.action = #selector(tabChanged(_:))
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tab switching

    @objc private func tabChanged(_ sender: NSSegmentedControl) {
        propertiesScroll.isHidden = sender.selectedSegment != 0
        effectsScroll.isHidden    = sender.selectedSegment != 1
    }

    func setToolMode(_ mode: ToolMode) {
        noToolView.isHidden = mode != .none
        let isArrow = mode == .arrow
        let isText  = mode == .text
        let isShape = mode == .shape
        arrowPropViews.forEach { $0.isHidden = !isArrow }
        textPropViews.forEach  { $0.isHidden = !isText }
        shapePropViews.forEach { $0.isHidden = !isShape }
        if mode != .none && tabControl.selectedSegment != 0 {
            tabControl.selectedSegment = 0
            propertiesScroll.isHidden = false
            effectsScroll.isHidden = true
        }
    }

    // MARK: Effects panel builders

    func addEffectSection(_ title: String, toggle: NSButton? = nil) {
        if !effectsStack.arrangedSubviews.isEmpty {
            let divider = NSBox(); divider.boxType = .separator
            effectsStack.addArrangedSubview(divider)
        }
        effectsStack.addArrangedSubview(makeSectionBox(title, toggle: toggle))
    }

    func addEffectRow(_ labelText: String, _ control: NSView, _ valLabel: NSTextField? = nil) {
        effectsStack.addArrangedSubview(makeSidebarRow(labelText, control, valLabel))
    }

    // MARK: Private builders

    private func makeSectionBox(_ title: String, toggle: NSButton? = nil) -> NSView {
        let lbl = NSTextField(labelWithString: title)
        lbl.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        lbl.textColor = .secondaryLabelColor
        lbl.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(lbl)
        NSLayoutConstraint.activate([
            lbl.topAnchor.constraint(equalTo: box.topAnchor, constant: 16),
            lbl.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -6),
            lbl.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
        ])
        if let toggle = toggle {
            toggle.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(toggle)
            NSLayoutConstraint.activate([
                toggle.centerYAnchor.constraint(equalTo: lbl.centerYAnchor),
                toggle.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            ])
        }
        return box
    }

    private func makeSidebarRow(_ labelText: String, _ control: NSView,
                                _ valLabel: NSTextField? = nil) -> NSView {
        let lbl = NSTextField(labelWithString: labelText)
        lbl.font = NSFont.systemFont(ofSize: 12)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        lbl.widthAnchor.constraint(equalToConstant: 60).isActive = true

        control.translatesAutoresizingMaskIntoConstraints = false
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)

        var views: [NSView] = [lbl, control]
        if let vl = valLabel {
            vl.translatesAutoresizingMaskIntoConstraints = false
            vl.widthAnchor.constraint(equalToConstant: 36).isActive = true
            vl.setContentHuggingPriority(.required, for: .horizontal)
            views.append(vl)
        }

        let row = NSStackView(views: views)
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.edgeInsets = NSEdgeInsets(top: 0, left: 14, bottom: 0, right: 14)
        row.heightAnchor.constraint(equalToConstant: 30).isActive = true
        return row
    }
}
