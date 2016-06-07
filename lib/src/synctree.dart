// Copyright (c) 2016, Rik Bellens. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

import 'event.dart';
import 'data_observer.dart';
import 'treestructureddata.dart';
import 'view.dart';
import 'operations/tree.dart';
import 'package:sortedmap/sortedmap.dart';
import 'tree.dart';

const _eventGenerator = const ViewEventGenerator(const TreeEventGenerator());

class SyncPoint {

  final Map<Filter,View> views = {};

  /**
   * Adds an event listener for events of [type] and for data filtered by
   * [filter].
   *
   * Returns true if no event listener for this [filter] was registered before
   * and therefore we should also listen for remote changes.
   *
   */
  bool addEventListener(String type, Filter filter, EventListener listener) {
    var view = views.putIfAbsent(filter,
        ()=>new View(new TreeStructuredData(filter: filter), _eventGenerator));
    //TODO: create view from parents
    var has = view.hasEventRegistrations;
    view.addEventListener(type, listener);
    view.generateInitialEvents(type).forEach(listener);
    return !has;
  }

  /**
   * Removes an event listener for events of [type] and for data filtered by
   * [filter].
   *
   * Returns true if no more event listerenes for this [filter] are registered
   * and therefore we should also unlisten for remote changes.
   *
   */
  bool removeEventListener(String type, Filter filter, EventListener listener) {
    var view = views.putIfAbsent(filter,
        ()=>new View(new TreeStructuredData(), _eventGenerator));
    view.removeEventListener(type, listener);
    if (!view.hasEventRegistrations) {
      views.remove(filter);
      return true;
    }
    return false;
  }

  /**
   * Applies an operation to the view for [filter] at this [SyncPoint] or all
   * views when [filter] is [null].
   */
  void applyOperation(Operation operation, Filter filter, ViewOperationSource source) {
    if (filter==null) {
      views.forEach((k,v) => v.applyOperation(new ViewOperation(source, operation)));
    } else {
      views[filter]?.applyOperation(new ViewOperation(source, operation));
    }
  }

  toString() => "SyncPoint[$views]";
}

class SyncTree {

  final TreeNode<Name,SyncPoint> root = _createNode();

  static _createNode() => new TreeNode(new SyncPoint());

  /**
   * Adds an event listener for events of [type] and for data at [path] and
   * filtered by [filter].
   *
   * Returns true if no event listener for this [path] and [filter] was
   * registered before and therefore we should also listen for remote changes.
   *
   */
  bool addEventListener(String type, Path<Name> path, Filter filter, EventListener listener) {
    return root.subtree(path, _createNode).value.addEventListener(type, filter, listener);
  }

  /**
   * Removes an event listener for events of [type] and for data at [path] and
   * filtered by [filter].
   *
   * Returns true if no more event listerenes for this [path] and [filter]
   * are registered and therefore we should also unlisten for remote changes.
   *
   */
  bool removeEventListener(String type, Path<Name> path, Filter filter, EventListener listener) {
    return root.subtree(path, _createNode).value.removeEventListener(type, filter, listener);
  }

  /**
   * Applies a user overwrite at [path] with [newData]
   */
  applyUserOverwrite(Path<Name> path, TreeStructuredData newData) {
    var operation = new _Operation.overwrite(path, newData);
    _applyOperationToSyncPoints(root, null, operation, ViewOperationSource.user);
  }

  /**
   * Applies a server overwrite at [path] with [newData]
   */
  applyServerOverwrite(Path<Name> path, Filter filter, TreeStructuredData newData) {
    var operation = new _Operation.overwrite(path, newData);
    _applyOperationToSyncPoints(root, filter, operation, ViewOperationSource.server);
  }

  /**
   * Applies a server merge at [path] with [changedChildren]
   */
  applyServerMerge(Path<Name> path, Filter filter, Map<Name,TreeStructuredData> changedChildren) {
    var operation = new _Operation.merge(path, changedChildren);
    _applyOperationToSyncPoints(root, filter, operation, ViewOperationSource.server);
  }

  /**
   * Applies a user merge at [path] with [changedChildren]
   */
  applyUserMerge(Path<Name> path, Map<Name,TreeStructuredData> changedChildren) {
    var operation = new _Operation.merge(path, changedChildren);
    _applyOperationToSyncPoints(root, null, operation, ViewOperationSource.user);
  }

  /**
   * Helper function to recursively apply an operation to a node in the
   * sync tree and all the relevant descendants.
   */
  static _applyOperationToSyncPoints(TreeNode<Name,SyncPoint> tree, Filter filter,
      TreeOperation<Name,Value> operation, ViewOperationSource type) {
    if (tree==null) return;
    tree.value.applyOperation(operation,filter,type);
    if (operation.path.isEmpty) return; // TODO: apply to descendants
    var child = operation.path.first;
    _applyOperationToSyncPoints(tree.children[child], filter, operation.operationForChild(child), type);
  }


}

class _Operation extends TreeOperation<Name, Value> {
  _Operation(Path<Name> path, Operation<TreeNode<Name, Value>> nodeOperation) :
        super(path, nodeOperation, ()=>new TreeStructuredData());

  _Operation.overwrite(Path<Name> path, TreeStructuredData value) :
      this(path, new Overwrite(value));

  _Operation.merge(Path<Name> path, Map<Name,TreeStructuredData> children) :
      this(path, new Merge(children));

  // TODO: ack operation
}