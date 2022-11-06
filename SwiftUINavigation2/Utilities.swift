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

public extension View {
  func navigationDestination<Value, Destination: View>(
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
      .navigationDestinationX(isPresented: self.$isPresented) {
        self.destination
      }
//      .uiKitNavigationDestination(isPresented: self.$isPresented) { self.destination }
//
//      .onChange(of: self.externalIsPresented) {
//        print("\(label) - externalIsPresented (parent side) did change to \($0), assigning to isPresented which is \(isPresented)")
//
//        self.isPresented = $0
//      }
//      .onChange(of: self.isPresented) {
//        print("\(label) - isPresented (child side) did change to \($0), assigning to externalIsPresented which is \(externalIsPresented)")
//        self.externalIsPresented = $0
//      }
//      .onAppear {
//        print("\(label) - onAppear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
////        if !isPresented {
//        self.isPresented = self.externalIsPresented
////        }
//      }
//      .onDisappear {
//        print("\(label) - onDisappear: isPresented:\(isPresented) - externalIsPresented:\(externalIsPresented)")
//      }
  }
}

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

//extension View {
//  func uiKitNavigationDestination<V>(isPresented: Binding<Bool>, @ViewBuilder destination: @escaping () -> V) -> some View where V: View {
//    self.modifier(UIKitNavigationDestination<V>(isPresented: isPresented, destination: destination))
//  }
//}
//
//struct UIKitNavigationDestination<Destination: View>: ViewModifier {
//  @Binding var isPresented: Bool
//  let destination: () -> Destination
//  @State var navigationController: UINavigationController?
//  @State var presentationRequest: Destination?
//  @State var hostingViewController: UIViewController?
//  func present(animated: Bool) {
//    guard self.hostingViewController == nil else { return }
//    guard let navigationController else { return }
//    guard let presentationRequest else { return }
//    let viewController = UIHostingController(rootView: presentationRequest)
//    // There are ordering issues here
//    self.presentationRequest = nil
//    self.hostingViewController = viewController
//    navigationController.pushViewController(viewController, animated: animated)
//  }
//
//  func dismiss(animated: Bool) {
//    guard let navigationController, let hostingViewController else { return }
//    let previous = navigationController.viewControllers.last(where: { $0 != hostingViewController })
//    if let previous {
//      navigationController.popToViewController(previous, animated: animated)
//    } else {
//      navigationController.popToRootViewController(animated: animated)
//    }
//  }
//
//  func body(content: Content) -> some View {
//    content
//      .onNavigationController { navigationController, _ in
//        self.navigationController = navigationController
//        self.present(animated: false)
//      }
//      .onAppear {
//        // This can cause problems when this is a parent view that is respawned on popping
//        if isPresented {
//          self.presentationRequest = destination()
//          self.present(animated: false)
//        } else {
////          self.dismiss(animated: false)
//        }
//      }
//      .onChange(of: self.isPresented) {
//        if $0 {
//          self.presentationRequest = destination()
//          self.present(animated: true)
//        } else {
//          self.dismiss(animated: true)
//        }
//      }
//  }
//}

import Combine
struct ObservableBinding<Value> {
  let subject: CurrentValueSubject<Value, Never>
  let binding: Binding<Value>

  init(_ binding: Binding<Value>) {
    let subject = CurrentValueSubject<Value, Never>(binding.wrappedValue)
    self.subject = subject
    self.binding = .init {
      binding.wrappedValue
    } set: {
      binding.transaction($1).wrappedValue = $0
      subject.value = $0
    }
  }
}

struct NavigationPathIDs: EnvironmentKey {
  static var defaultValue: [UUID] = []
}

extension EnvironmentValues {
  var navigationPathIDs: [UUID] {
    get { self[NavigationPathIDs.self] }
    set { self[NavigationPathIDs.self] = newValue }
  }
}


extension View {
  public func registerNavigationCoordinator() -> some View {
    self.modifier(Navigation.CoordinatorModifier())
  }
}

extension Navigation {
  struct CoordinatorModifier: ViewModifier {
    @StateObject var coordinator: Coordinator = .init()
    
    func body(content: Content) -> some View {
      content
        .environmentObject(coordinator)
        .onNavigationController { navigationController, _ in
          coordinator.navigationController = navigationController
        }
    }
  }
}

extension View {
 public func navigationDestinationX<Destination: View>(
    isPresented: Binding<Bool>,
    @ViewBuilder destination: @escaping () -> Destination) -> some View {
      self.modifier(Navigation.DestinationModifier(isPresented: isPresented, destination: destination))
    }
}

extension Navigation {
  struct DestinationModifier<Destination: View>: ViewModifier {
    @State var destinationID: UUID = .init()
    @EnvironmentObject var coordinator: Coordinator
    @Environment(\.navigationPathIDs) var navigationPathIDs
    let destination: () -> Destination
    @Binding var isPresented: Bool
    
    init(
      isPresented: Binding<Bool>,
      destination: @escaping () -> Destination
    ) {
      self.destination = destination
      self._isPresented = isPresented
    }

    func body(content: Content) -> some View {
      content
        .onNavigationController { navigationController, hostingViewController in
          coordinator.register(
            destinationID: destinationID,
            navigationController: navigationController,
            hostingController: hostingViewController
          )
        }
        .onAppear {
          coordinator.register(
            destinationID: destinationID,
            parents: navigationPathIDs,
            isPresented: $isPresented,
            destination: {
              destination()
                .environmentObject(coordinator)
                .environment(\.navigationPathIDs, navigationPathIDs + [destinationID])
            }
          )
        }
    }
  }
}

enum Navigation {}
extension Navigation {
  final class Coordinator: ObservableObject {
    let register = Register()
    var navigationController: UINavigationController?
    var cancellable: AnyCancellable?
    init() {
      cancellable = register.$path.sink { [navigationController] path in
        guard let navigationController else { return }
        let root = navigationController.viewControllers.first!
        let remainder = path.map(\.host)
        navigationController.setViewControllers([root] + remainder, animated: true)
      }
    }
  }
}

extension Navigation.Coordinator {
  func register(
    destinationID: UUID,
    navigationController: UINavigationController?,
    hostingController: UIViewController?
  ) {
    if self.navigationController != navigationController, self.navigationController != nil {
      print("Warning, nested navigation. This currently is not supported.")
    }
    self.navigationController = navigationController
    self.register.presentingHostForDestinationID[destinationID] = hostingController
  }

  func register<D: View>(
    destinationID: UUID,
    parents: [UUID],
    isPresented: Binding<Bool>,
    destination: @escaping () -> D
  ) {
    self.register.register(
      destinationID: destinationID,
      parents: parents,
      isPresented: isPresented,
      destination: destination
    )
  }
}

extension Navigation.Coordinator {
  final class Register {
    let rootViewControllerID: UUID = .init()
    @Published var destinationForDestinationID: [UUID: Navigation.Destination] = [:]
    @Published var presentingHostForDestinationID: [UUID: UIViewController] = [:]
    @Published var presentationStates: [UUID: Bool] = [:]

    @Published var path: [Navigation.PathComponent] = []

    var observedBindingsCancellables: [UUID: AnyCancellable] = [:]
    var cancellable: AnyCancellable?

    func register<D: View>(
      destinationID: UUID,
      parents: [UUID],
      isPresented: Binding<Bool>,
      destination: @escaping () -> D
    ) {
      let observableBinding = ObservableBinding(isPresented)

      self.observedBindingsCancellables[destinationID] = Publishers.CombineLatest(
        self.$presentationStates.removeDuplicates(),
        observableBinding.subject.map { (destinationID, $0) }.print()
      ).map { presentationStates, idAndState in
        var presentationStates = presentationStates
        presentationStates[idAndState.0] = idAndState.1
        return presentationStates
      }.sink { [weak self] in
        self?.presentationStates = $0
      }

      self.destinationForDestinationID[destinationID] = .init(
        id: destinationID,
        parents: parents,
        isPresented: observableBinding,
        content: { AnyView(erasing: destination()) }
      )
    }

    init() {
      self.cancellable = Publishers.CombineLatest3(
        self.$destinationForDestinationID,
        self.$presentingHostForDestinationID,
        self.$presentationStates
      )
      .map { destinationForDestinationID, presentingHostForDestinationID, presentationStates in
        presentationStates
          .filter { $0.value }.keys
          .compactMap { destinationForDestinationID[$0] }
          .sorted { $0.isParent(of: $1) ?? true }
          .map { destination in
            let host: UIViewController
            if
              let parent = presentingHostForDestinationID[destination.id],
              let existingHost = parent.navigationController?.viewControllers
              .first(where: {
                ($0 as? Navigation.HostingController)?.identifier == destination.id
              }) {
              host = existingHost
            } else {
              host = Navigation.HostingController(identifier: destination.id, destination: destination.content)
            }

            return Navigation.PathComponent(
              id: destination.id,
              host: host
            )
          }
      }
      .sink { [weak self] in
        self?.path = $0
      }
    }
  }
}

extension Navigation {
  struct PathComponent: Equatable {
    let id: UUID
    let host: UIViewController
  }
}

extension Navigation {
  struct Destination: Identifiable {
    let id: UUID
    let parents: [UUID]
    let isPresented: ObservableBinding<Bool>
    let content: () -> AnyView
    init(
      id: UUID,
      parents: [UUID],
      isPresented: ObservableBinding<Bool>,
      content: @escaping () -> AnyView
    ) {
      self.id = id
      self.parents = parents
      self.isPresented = isPresented
      self.content = content
    }

    func isParent(of other: Destination) -> Bool? {
      let path = self.parents + [self.id]
      let otherPath = other.parents + [other.id]

      if path.count < otherPath.count, otherPath.starts(with: path) {
        return true
      } else if otherPath.count < path.count, path.starts(with: otherPath) {
        return false
      } else {
        return nil
      }
    }
  }
}

extension Navigation {
  final class HostingController: UIHostingController<AnyView> {
    let identifier: UUID
    init(
      identifier: UUID,
      destination: () -> AnyView
    ) {
      self.identifier = identifier
      super.init(rootView: destination())
    }

    @available(*, unavailable)
    required init?(coder aDecoder: NSCoder) {
      fatalError("init(coder:) has not been implemented")
    }
  }
}
