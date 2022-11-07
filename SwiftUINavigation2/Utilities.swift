import CasePaths
import Foundation
import SwiftUI

public extension Binding {
  func isPresent<Wrapped>() -> Binding<Bool>
    where Value == Wrapped?
  {
    .init(
      get: { self.wrappedValue != nil },
      set: { isPresent, transaction in
        if !isPresent {
          self.transaction(transaction).wrappedValue = nil
        }
      }
    )
  }

  init?(unwrapping base: Binding<Value?>) {
    self.init(unwrapping: base, case: /Optional.some)
  }

  init?<Enum>(unwrapping enum: Binding<Enum>, case casePath: CasePath<Enum, Value>) {
    guard var `case` = casePath.extract(from: `enum`.wrappedValue)
    else { return nil }

    self.init(
      get: {
        `case` = casePath.extract(from: `enum`.wrappedValue) ?? `case`
        return `case`
      },
      set: {
        `case` = $0
        `enum`.transaction($1).wrappedValue = casePath.embed($0)
      }
    )
  }
}

enum NavigationPathKey: EnvironmentKey {
  static var defaultValue: NavigationPath = .init()
}

extension EnvironmentValues {
  var navigationPath: NavigationPath {
    get { self[NavigationPathKey.self] }
    set { self[NavigationPathKey.self] = newValue }
  }
}

struct NavigationDestinationValue<Tag, Value: Hashable>: Hashable {
  var value: Value
}

struct NavigationPathDestination<Value: Hashable, Source: View, Destination: View>: ViewModifier {
  init() {}

  @Environment(\.navigationPath) var navigationPath
  func body(content: Content) -> some View {
    content
      .navigationDestination(for: NavigationDestinationValue<(Source, Destination), Value>.self) { _ in
      }
  }
}




public extension View {
  func navigationDestination<Value, Destination: View>(
    label: String,
    unwrapping value: Binding<Value?>,
    @ViewBuilder destination: (Binding<Value>) -> Destination
  ) -> some View {
    let destination = Binding(unwrapping: value).map(destination)
//    print("YY:\(label) - \(Self.self)")
    
   return  _NavigationDestinationWrapper(
      label: label,
      isPresented: value.isPresent(),
      content: self,
      destination: destination
    )
//    return
//      self
//        .modifier(
//          _NavigationDestination(
//            label: label,
//            structuralID: ObjectIdentifier(Self.self),
//            isPresented: value.isPresent(),
//            destination: destination
//          )
//        )
  }
}

extension View {
  func observeNavigationBindings() -> some View {
    self.overlayPreferenceValue(NavigationBindingKey.self, alignment: .bottom) { bindings in
      let bindings = bindings.sorted(by: { $0.value.label < $1.value.label })
      VStack {
        ForEach(bindings, id: \.0) {
          BindingView(
            id: $0.value.id,
            label: $0.value.label,
            structuralID:$0.value.structuralID,
            isAppeared: $0.value.isAppeared,
            externalIsPresented: $0.value.$externalBinding,
            internalIsPresented: $0.value.$internalBinding
          )
        }
      }
    }
  }
}

struct BindingComponent: Identifiable, Hashable {
  var id: UUID
  var isOn: Bool
}

extension BindingComponent: EnvironmentKey {
  static var defaultValue: [BindingComponent] = []
}

extension EnvironmentValues {
  var bindingComponents: [BindingComponent] {
    get { self[BindingComponent.self] }
    set { self[BindingComponent.self] = newValue }
  }
}

struct BindingView: View {
  var id: UUID
  var label: String
  var structuralID: ObjectIdentifier
  var isAppeared: Bool
  @Binding var externalIsPresented: Bool
  @Binding var internalIsPresented: Bool
  var body: some View {
    VStack {
      HStack {
        Image(systemName: "eye")
          .imageScale(.small)
          .symbolVariant(isAppeared ? .circle.fill : .slash.circle)
        Text(label)
        Text(id.uuidString).font(.caption2)
      }
      HStack {
        Text(String(describing: structuralID))
          .lineLimit(1)
          .font(.caption2)
      }
    }
    .monospaced()
      .foregroundColor(self.internalIsPresented ? .blue : .red)
      .onChange(of: self.externalIsPresented) {
        print("\(self.label) - externalIsPresented (parent side) did change to \($0), assigning to isPresented which is \(self.internalIsPresented)")

        self.internalIsPresented = $0

      }
      .onChange(of: self.internalIsPresented) {
        print("\(self.label) - isPresented (child side) did change to \($0), assigning to externalIsPresented which is \(self.externalIsPresented)")
        self.externalIsPresented = $0
      }
  }
}

struct NavigationBinding {
  var label: String
  var id: UUID
  var structuralID: ObjectIdentifier
  var isAppeared: Bool
  @Binding var externalBinding: Bool
  @Binding var internalBinding: Bool
}

struct NavigationBindingKey: PreferenceKey {
  static var defaultValue: [ObjectIdentifier: NavigationBinding] { [:] }
  static func reduce(value: inout [ObjectIdentifier: NavigationBinding], nextValue: () -> [ObjectIdentifier: NavigationBinding]) {
//    print("Merging \(nextValue().keys) with \(value.keys)")
    value.merge(nextValue(), uniquingKeysWith: { _, key in key })
  }
}

struct Pair<T, U> {}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct _NavigationDestinationWrapper<Content: View, Destination: View>: View {
  let structuralID: ObjectIdentifier
  let label: String
  let content: Content
  let destination: Destination
  @Binding var externalIsPresented: Bool
  @State var isPresented = false

  @State var identifier = UUID()
  @Environment(\.bindingComponents) var bindingComponents
  @State var viewID: UUID?
  @State var isAppeared: Bool = false
  
  init(
    label: String,
    isPresented: Binding<Bool>,
    content: Content,
    destination: Destination
  ) {
    self.label = label
    self.structuralID = ObjectIdentifier(Pair<Content, Destination>.self)
    self._externalIsPresented = isPresented
    self.content = content
    self.destination = destination
  }

  public var body: some View {
    content

      .preference(
        key: NavigationBindingKey.self,
        value: [structuralID: .init(
          label:label,
          id: identifier,
          structuralID: structuralID,
          isAppeared: isAppeared,
          externalBinding: self.$externalIsPresented,
          internalBinding: self.$isPresented
        )]
      )
      .onAppear {
        self.isAppeared = true
        self.isPresented = self.externalIsPresented
      }
      .onDisappear {
        self.isAppeared = false
      }
      .navigationDestination(isPresented: self.$externalIsPresented) {
        self.destination
      }
  }
}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct _NavigationDestination<Destination: View>: ViewModifier {
  let structuralID: ObjectIdentifier
  let label: String
  let destination: Destination
  @Binding var externalIsPresented: Bool
  @State var isPresented = false

  @State var identifier = UUID()
  @Environment(\.bindingComponents) var bindingComponents
  @State var viewID: UUID?
  @State var isAppeared: Bool = false
  init(
    label: String,
    structuralID: ObjectIdentifier,
    isPresented: Binding<Bool>,
    destination: Destination
  ) {
    self.label = label
    self.structuralID = structuralID
    self._externalIsPresented = isPresented
    self.destination = destination
  }

  public func body(content: Content) -> some View {
    content
      .navigationDestination(isPresented: self.$isPresented) {
        self.destination
      }
      .onAppear {
//        print("\(label) - onAppear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
        print("\(label) - onAppear:\(identifier)")
        self.isAppeared = true
        self.isPresented = self.externalIsPresented
      }
      .onDisappear {
        print("\(label) - onDisappear:\(identifier)")
        self.isAppeared = false
//        print("\(label) - onDisappear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
      }
      .preference(
        key: NavigationBindingKey.self,
        value: [structuralID: .init(
          label:label,
          id: identifier,
          structuralID: structuralID,
          isAppeared: isAppeared,
          externalBinding: self.$externalIsPresented,
          internalBinding: self.$isPresented
        )]
      )
  }
}



//struct ViewID: UIViewRepresentable {
//  let label: String
//  @Binding var id: UUID?
//  func makeUIView(context: Context) -> UIViewID {
//    UIViewID()
//  }
//
//  func updateUIView(_ uiView: UIViewID, context: Context) {
////    id = uiView.id
//    print("id for \(label): \(uiView.id)")
//  }
//  final class UIViewID: UIView {
//    let id = UUID()
//  }
//}




struct DismissByState: EnvironmentKey {
  static var defaultValue: Self { .init {} }
  let dismiss: () -> Void

  init(_ dismiss: @escaping () -> Void) {
    self.dismiss = dismiss
  }

  func callAsFunction() {
    self.dismiss()
  }
}

extension EnvironmentValues {
  var dismissByState: DismissByState {
    get { self[DismissByState.self] }
    set { self[DismissByState.self] = newValue }
  }
}

public extension View {
  @available(iOS 15.0, *)
  func present<Model: ObservableObject, Value>(
    with model: Model, value: @escaping (Model) -> Value?
  ) -> some View {
    self.modifier(NavigationDestinationPresenter(model: model, value: value))
  }
}

@available(iOS 15.0, *)
struct NavigationDestinationPresenter<Model: ObservableObject>: ViewModifier {
  @ObservedObject var model: Model
  @State var navigationController: UINavigationController?
  @State var hostingViewController: UIViewController?
  @Environment(\.dismiss) var dismissFromEnvironment
  func dismiss() {
//    dismissFromEnvironment()
    if let previous = navigationController?.viewControllers.last(where: {
      $0 != hostingViewController
    }) {
      self.navigationController?.popToViewController(previous, animated: true)
    }
  }

  @State var isPresented: Bool = false
  let shouldPresent: () -> Bool

  init<Value>(model: Model, value: @escaping (Model) -> Value?) {
    self.model = model
    self.shouldPresent = {
      value(model) != nil
    }
  }

  func body(content: Content) -> some View {
    content
      .onNavigationController {
        self.navigationController = $0
        self.hostingViewController = $1
      }
      .onAppear {
        isPresented = true
        if !shouldPresent() {
          dismiss()
        }
      }
      .onChange(of: self.shouldPresent()) { shouldPresent in
        if !shouldPresent, isPresented {
          isPresented = false
          dismiss()
        }
      }
  }
}

extension View {
  func onNavigationController(
    _ perform: @escaping (
      _ navigationController: UINavigationController?, _ hostingViewController: UIViewController?
    ) -> Void
  ) -> some View {
    self
      .background(NavigationControllerProbe(onNavigationController: perform))
  }
}

struct NavigationControllerProbe: UIViewControllerRepresentable {
  let onNavigationController: (UINavigationController?, UIViewController?) -> Void

  final class Coordinator {
    let onNavigationController: (UINavigationController?, UIViewController?) -> Void
    weak var navigationController: UINavigationController?
    weak var hostingController: UIViewController?

    init(onNavigationController: @escaping (UINavigationController?, UIViewController?) -> Void) {
      self.onNavigationController = onNavigationController
    }

    func update(navigationController: UINavigationController?, hostingController: UIViewController?)
    {
      defer {
        self.navigationController = navigationController
        self.hostingController = hostingController
      }
      if navigationController != self.navigationController
        || hostingController != self.hostingController
      {
        self.onNavigationController(navigationController, hostingController)
      }
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onNavigationController: self.onNavigationController)
  }

  func makeUIViewController(context: Context) -> ViewController {
    ViewController(onNavigationController: context.coordinator.update)
  }

  func updateUIViewController(_ uiViewController: ViewController, context: Context) {}

  final class ViewController: UIViewController {
    let onNavigationController: (UINavigationController?, UIViewController?) -> Void
    init(onNavigationController: @escaping (UINavigationController?, UIViewController?) -> Void) {
      self.onNavigationController = onNavigationController
      super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    // Seems to be soon enough. Alternative: viewWillAppear.
    override func willMove(toParent parent: UIViewController?) {
      super.willMove(toParent: parent)
      self.update()
    }

    func update() {
      self.onNavigationController(self.navigationController, self.findHostingController(from: self))
    }

    private func findHostingController(from viewController: UIViewController?) -> UIViewController?
    {
      guard let viewController = viewController else { return nil }
      if let parent = viewController.parent, parent == navigationController {
        return viewController
      }
      return self.findHostingController(from: viewController.parent)
    }
  }
}

struct DeferredView<Content: View>: View {
  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  let content: Content
  @State var didAppear: Bool = false
  var body: some View {
    if !didAppear {
      Color.red
        .onAppear {
          DispatchQueue.main.async {
            didAppear = true
          }
        }
    } else {
      content
    }
  }
}
