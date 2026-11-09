//
//  MainSidebarView.swift
//  Brew
//

import BrewAccessibilityID
import BrewFeatureInstalled
import BrewUIComponents
import SwiftUI

struct MainSidebarView: View {
    @Binding var selection: SidebarItem

    private static let sections: [(title: String, items: [SidebarItem])] = [
        (String(localized: "Library", bundle: #bundle, comment: "Sidebar section: packages on this Mac"), [.installed, .upgrades]),
        (String(localized: "Find", bundle: #bundle, comment: "Sidebar section: finding new packages"), [.discover, .assistant]),
        (String(localized: "Manage", bundle: #bundle, comment: "Sidebar section: services and taps"), [.services, .taps]),
        (String(localized: "Health", bundle: #bundle, comment: "Sidebar section: diagnostics and configuration"), [.doctor, .configuration]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            wordmark
                .padding(.horizontal, BrewSpacing.lg)
                .padding(.top, BrewSpacing.md)

            ForEach(Self.sections, id: \.title) { section in
                Text(section.title)
                    .font(.brewCaption)
                    .foregroundStyle(Color.brewTextSecondary)
                    .padding(.horizontal, BrewSpacing.lg)
                    .padding(.top, BrewSpacing.xl)
                    .padding(.bottom, BrewSpacing.xs)
                    .accessibilityAddTraits(.isHeader)
                VStack(spacing: BrewSpacing.xxs) {
                    ForEach(section.items) { item in
                        sidebarRow(
                            title: item.title,
                            systemImage: item.systemImage,
                            item: item,
                            trailingAccessory: {
                                if item == .upgrades {
                                    UpgradesSidebarBadge()
                                }
                            },
                        )
                    }
                }
                .padding(.horizontal, BrewSpacing.sm)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.brewSurface)
        // `.contain` makes the sidebar itself an addressable container element without flattening
        // the rows inside it, so UI tests can scope a query to the sidebar.
        .accessibilityElement(children: .contain)
        .axid(.sidebar)
    }

    private var wordmark: some View {
        HStack(spacing: BrewSpacing.sm) {
            Image(systemName: "flask.fill")
                .foregroundStyle(Color.brewTextBrand)
                .accessibilityHidden(true)
            Text(verbatim: "Brewly")
                .font(.brewTitle3)
                .foregroundStyle(Color.brewTextPrimary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        item: SidebarItem,
        @ViewBuilder trailingAccessory: () -> some View = { EmptyView() },
    ) -> some View {
        let isSelected = selection == item
        Button {
            selection = item
        } label: {
            HStack(spacing: BrewSpacing.sm) {
                Image(systemName: systemImage)
                    .imageScale(.medium)
                    .foregroundStyle(isSelected ? Color.brewTextBrand : Color.brewTextSecondary)
                    .frame(width: BrewLayout.sidebarIconWidth)
                Text(title)
                    .font(.brewBody)
                    .foregroundStyle(isSelected ? Color.brewTextBrand : Color.brewTextPrimary)
                Spacer(minLength: 0)
                trailingAccessory()
            }
            .padding(.leading, BrewSpacing.sm)
            .padding(.trailing, BrewSpacing.md)
            .padding(.vertical, BrewSpacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: BrewRadius.md)
                    .fill(isSelected ? Color.brewBrandTint : Color.clear)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .axid(.sidebarItem(item.axDestination))
    }
}

#Preview {
    MainSidebarView(selection: .constant(.installed))
        .frame(width: BrewLayout.sidebarWidth, height: 400)
}
