import CasePaths
import Foundation
import SwiftUI

extension Binding {
  public func isPresent<Wrapped>() -> Binding<Bool>
  where Value == Wrapped? {
    .init(
      get: { self.wrappedValue != nil },
      set: { isPresent, transaction in
        if !isPresent {
          self.transaction(transaction).wrappedValue = nil
        }
      }
    )
  }

  public init?(unwrapping base: Binding<Value?>) {
    self.init(unwrapping: base, case: /Optional.some)
  }

  public init?<Enum>(unwrapping enum: Binding<Enum>, case casePath: CasePath<Enum, Value>) {
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

extension View {
  public func navigationDestination<Value, Destination: View>(
    label: String,
    unwrapping value: Binding<Value?>,
    @ViewBuilder destination: (Binding<Value>) -> Destination
  ) -> some View {
    let destination = Binding(unwrapping: value).map(destination)
    return
      self
      .modifier(
        _NavigationDestination(
          label: label,
          isPresented: value.isPresent(),
          destination: destination
        )
      )
  }

}

@available(iOS 16, macOS 13, tvOS 16, watchOS 9, *)
public struct _NavigationDestination<Destination: View>: ViewModifier {
  let label: String
  let destination: Destination
  @Binding var externalIsPresented: Bool
  @State var isPresented = false

  init(
    label: String,
    isPresented: Binding<Bool>,
    destination: Destination
  ) {
    self.label = label
    self._externalIsPresented = isPresented
    self.destination = destination
  }

  public func body(content: Content) -> some View {
    content
      .uiKitNavigationDestination(isPresented: self.$isPresented) { self.destination }

      .onChange(of: self.externalIsPresented) {
        print("\(label) - externalIsPresented (parent side) did change to \($0), assigning to isPresented which is \(isPresented)")

        self.isPresented = $0

      }
      .onChange(of: self.isPresented) {
        print("\(label) - isPresented (child side) did change to \($0), assigning to externalIsPresented which is \(externalIsPresented)")
        self.externalIsPresented = $0
      }
      .onAppear {
        print("\(label) - onAppear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
//        if !isPresented {
          self.isPresented = self.externalIsPresented
//        }
      }
      .onDisappear {
        print("\(label) - onDisappear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
      }
  }
}


struct DismissByState: EnvironmentKey {
  static var defaultValue: Self { .init {} }
  let dismiss: () -> Void

  init(_ dismiss: @escaping () -> Void) {
    self.dismiss = dismiss
  }
  func callAsFunction() {
    dismiss()
  }
}
extension EnvironmentValues {
  var dismissByState: DismissByState {
    get { self[DismissByState.self] }
    set { self[DismissByState.self] = newValue }
  }
}

extension View {
  @available(iOS 15.0, *)
  public func present<Model: ObservableObject, Value>(
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
      return value(model) != nil
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
      .onChange(of: shouldPresent()) { shouldPresent in
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
    Coordinator(onNavigationController: onNavigationController)
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

    required init?(coder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }

    // Seems to be soon enough. Alternative: viewWillAppear.
    override func willMove(toParent parent: UIViewController?) {
      super.willMove(toParent: parent)
      update()
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
      return findHostingController(from: viewController.parent)
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


extension View {
  func uiKitNavigationDestination<V>(isPresented: Binding<Bool>, @ViewBuilder destination: @escaping () -> V) -> some View where V : View {
    self.modifier(UIKitNavigationDestination<V>(isPresented: isPresented, destination: destination))
  }
}
struct UIKitNavigationDestination<Destination: View>: ViewModifier {
  @Binding var isPresented: Bool
  let destination: () -> Destination
  @State var navigationController: UINavigationController?
  @State var presentationRequest: Destination?
  @State var hostingViewController: UIViewController?
  func present(animated: Bool) {
    guard hostingViewController == nil else { return }
    guard let navigationController else { return }
    guard let presentationRequest else { return }
    let viewController = UIHostingController(rootView: presentationRequest)
    // There are ordering issues here
    self.presentationRequest = nil
    self.hostingViewController = viewController
    navigationController.pushViewController(viewController, animated: animated)
  }
  
  func dismiss(animated: Bool) {
    guard let navigationController, let hostingViewController else { return }
    let previous = navigationController.viewControllers.last(where:  { $0 != hostingViewController })
    if let previous {
      navigationController.popToViewController(previous, animated: animated)
    } else {
      navigationController.popToRootViewController(animated: animated)
    }
  }
  
  func body(content: Content) -> some View {
    content
      .onNavigationController{ navigationController, hostingViewController in
        self.navigationController = navigationController
        self.present(animated: false)
      }
      .onAppear {
        // This can cause problems when this is a parent view that is respawned on popping
        if isPresented {
          self.presentationRequest = destination()
          self.present(animated: false)
        } else {
//          self.dismiss(animated: false)
        }
      }
      .onChange(of: isPresented) {
        if $0 {
          self.presentationRequest = destination()
          self.present(animated: true)
        } else {
          self.dismiss(animated: true)
        }
      }
  }
}
