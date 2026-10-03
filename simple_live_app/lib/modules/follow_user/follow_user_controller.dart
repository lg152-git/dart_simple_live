// ignore_for_file: invalid_use_of_protected_member

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/platform_utils.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/follow_user_tag.dart';
import 'package:simple_live_app/modules/multi_room/multi_room_models.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/current_room_service.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/desktop_multi_window_service.dart';
import 'package:simple_live_app/services/follow_service.dart';

class FollowGroupOption {
  final String id;
  final String title;
  final int? liveStatus;

  const FollowGroupOption({
    required this.id,
    required this.title,
    this.liveStatus,
  });
}

class FollowUserController extends BasePageController<FollowUser> {
  static const int paginationThreshold = 400;
  static const String allTagId = "0";
  StreamSubscription<dynamic>? onUpdatedIndexedStream;
  StreamSubscription<dynamic>? onUpdatedListStream;

  var selectedGroupId = "all".obs;
  var selectedTagId = allTagId.obs;
  var searchKeyword = "".obs;
  var multiSelectMode = false.obs;
  RxSet<String> selectedMultiRoomKeys = <String>{}.obs;
  var currentDisplayPage = 1.obs;
  var totalDisplayPages = 1.obs;
  var paginationEnabled = false.obs;
  DateTime? _lastEnterRefreshAt;
  bool _enterRefreshInFlight = false;
  RxList<FollowUserTag> tagList = [
    FollowUserTag(id: "0", tag: "全部", userId: []),
    FollowUserTag(id: "1", tag: "开播中", userId: []),
    FollowUserTag(id: "2", tag: "未开播", userId: []),
  ].obs;

  // 用户自定义标签
  RxList<FollowUserTag> userTagList = <FollowUserTag>[].obs;

  @override
  void onInit() {
    pageSize = AppSettingsController.instance.followPageSize.value;
    _restoreGroupSelection();
    unawaited(_loadInitialData());
    onUpdatedIndexedStream = EventBus.instance.listen(
      EventBus.kBottomNavigationBarClicked,
      (index) {
        if (index == 1) {
          scrollToTopOrRefresh();
        }
      },
    );
    onUpdatedListStream =
        FollowService.instance.updatedListStream.listen((event) {
      updateTagList();
      filterData();
    });
    super.onInit();
  }

  Future<void> _loadInitialData() async {
    await refreshData(forceStatus: false);
    await _maybeRefreshOnEnter();
  }

  Future<void> _maybeRefreshOnEnter() async {
    final now = DateTime.now();
    // 自动刷新现在无条件生效：只要列表非空就进页快刷，
    // 不再查 followRefreshOnEnter 开关（该开关默认是关的，
    // 之前会导致进页根本不刷）。
    if (FollowService.instance.followList.isEmpty || _enterRefreshInFlight) {
      return;
    }
    if (_lastEnterRefreshAt != null &&
        now.difference(_lastEnterRefreshAt!) <
            BasePageController.refreshCooldown) {
      return;
    }
    _enterRefreshInFlight = true;
    _lastEnterRefreshAt = now;
    try {
      await FollowService.instance.refreshSelectedStatus(
        FollowService.instance.buildEnterPageRefreshTargets(list.toList()),
        // 进页是用户主动行为，force:true 绕过 30 秒全局冷却，
        // 确保每次进页都能立即刷状态。
        force: true,
        scope: FollowRefreshScope.page(
          scopeKey: FollowService.instance.buildPageRefreshScopeKey(
            currentRefreshScopeKey,
          ),
        ),
        allowDetailRefresh: false,
        // 进页快刷：并发提到 4，只查开播状态不拉详情，
        // 让直播中的主播尽快出现。
        statusConcurrency: 4,
        statusOnly: true,
      );
      // 封面/标题/开播时间等详情由后台静默补齐，不挡进页体验。
      unawaited(FollowService.instance.refreshEnterPageDetails());
    } finally {
      _enterRefreshInFlight = false;
    }
    filterData();
  }

  void _restoreGroupSelection() {
    // 分组默认"全部"：不再恢复上次持久化的"开播中/未开播"，
    // 每次进页都是"全部"，避免用户要往下滚找未开播的主播。
    selectedGroupId.value = "all";
  }

  @override
  Future refreshData({bool forceStatus = true}) async {
    pageSize = AppSettingsController.instance.followPageSize.value;
    await FollowService.instance.loadData(
      updateStatus: forceStatus,
      forceUpdateStatus: forceStatus,
    );
    updateTagList();
    filterData();
  }

  @override
  Future<List<FollowUser>> getData(int page, int pageSize) async {
    final items = _buildFilteredList();
    final start = (page - 1) * pageSize;
    if (start >= items.length) {
      return Future.value([]);
    }
    final end = (start + pageSize).clamp(0, items.length).toInt();
    return items.sublist(start, end);
  }

  void updateTagList() {
    userTagList.assignAll(FollowService.instance.followTagList);
    tagList.value = tagList.take(3).toList();
    for (var i in userTagList) {
      if (!tagList.contains(i)) {
        tagList.add(i);
      }
    }
    if (!filterTagOptions.any((tag) => tag.id == selectedTagId.value)) {
      selectedTagId.value = allTagId;
    }
  }

  void filterData() {
    final items = _buildFilteredList();
    _rebuildPagedList(items);
    pageEmpty.value = items.isEmpty;
  }

  void _rebuildPagedList(List<FollowUser> items) {
    pageSize = AppSettingsController.instance.followPageSize.value;
    paginationEnabled.value = items.length > paginationThreshold;
    if (!paginationEnabled.value) {
      currentDisplayPage.value = 1;
      totalDisplayPages.value = 1;
      currentPage = items.isEmpty ? 1 : 2;
      canLoadMore.value = false;
      list.assignAll(items);
      _scrollToCurrentRoom(_currentRoomIndexIn(items), items.length);
      _requestVisiblePreviews(items);
      return;
    }

    final maxPageSize = ((items.length / 2).floor() + 1).clamp(2, items.length);
    final effectivePageSize = pageSize.clamp(2, maxPageSize).toInt();
    if (effectivePageSize != pageSize) {
      pageSize = effectivePageSize;
      AppSettingsController.instance.setFollowPageSize(effectivePageSize);
    }
    totalDisplayPages.value =
        (items.length / effectivePageSize).ceil().clamp(1, items.length);
    if (currentDisplayPage.value > totalDisplayPages.value) {
      currentDisplayPage.value = totalDisplayPages.value;
    }
    if (currentDisplayPage.value < 1) {
      currentDisplayPage.value = 1;
    }
    final start = (currentDisplayPage.value - 1) * effectivePageSize;
    final end = (start + effectivePageSize).clamp(0, items.length).toInt();
    list.assignAll(items.sublist(start, end));
    currentPage = currentDisplayPage.value;
    canLoadMore.value = false;
    final currentIndex = _currentRoomIndexIn(list);
    _scrollToCurrentRoom(currentIndex, list.length);
    _requestVisiblePreviews(list.toList());
  }

  List<FollowUser> get currentPageTargets => list.toList();

  String get currentRefreshScopeKey {
    return "${currentDisplayPage.value}:${selectedTagId.value}:${selectedGroupId.value}";
  }

  // 标签行只返回用户自定义标签，"全部"按钮已删掉；
  // 选中"全部"（allTagId）时由 selectedTagOption 回退到不选标签。
  List<FollowUserTag> get filterTagOptions => userTagList.toList();

  FollowUserTag get selectedTagOption {
    final matched = filterTagOptions
        .where((tag) => tag.id == selectedTagId.value)
        .firstOrNull;
    if (matched != null) {
      return matched;
    }
    // "全部"（allTagId）不再作为可选项；选中它时回退到不选标签。
    final allTag = tagList.firstWhere(
      (tag) => tag.id == allTagId,
      orElse: () => tagList.first,
    );
    return allTag;
  }

  String get selectedTagName => selectedTagOption.tag;

  String get refreshTagLabel =>
      selectedTagId.value == allTagId ? "全部" : selectedTagName;

  Future<void> refreshCurrentPageStatus() async {
    final pageItems =
        paginationEnabled.value ? currentPageTargets : _buildFilteredList();
    await FollowService.instance.refreshSelectedStatus(
      FollowService.instance.buildPageFrontTargets(pageItems),
      force: true,
      scope: FollowRefreshScope.page(
        scopeKey: FollowService.instance.buildPageRefreshScopeKey(
          currentRefreshScopeKey,
        ),
      ),
    );
    filterData();
  }

  Future<void> refreshAllStatus() async {
    final selectedTag = selectedTagOption;
    final isAll = selectedTag.id == allTagId;
    await FollowService.instance.refreshSelectedStatus(
      _buildSelectedTagList(),
      force: true,
      scope: isAll
          ? const FollowRefreshScope.all()
          : FollowRefreshScope.tag(
              tagId: selectedTag.id,
              tagName: selectedTag.tag,
            ),
    );
    filterData();
  }

  void goToNextPage() {
    if (!paginationEnabled.value ||
        currentDisplayPage.value >= totalDisplayPages.value) {
      return;
    }
    currentDisplayPage.value += 1;
    filterData();
  }

  void goToPreviousPage() {
    if (!paginationEnabled.value || currentDisplayPage.value <= 1) {
      return;
    }
    currentDisplayPage.value -= 1;
    filterData();
  }

  int _currentRoomIndexIn(List<FollowUser> items) {
    final currentKey = CurrentRoomService.instance.currentKey;
    if (currentKey.isEmpty) {
      return -1;
    }
    return items
        .indexWhere((item) => "${item.siteId}_${item.roomId}" == currentKey);
  }

  void _scrollToCurrentRoom(int index, int visibleCount) {
    if (index < 0 || index >= visibleCount) {
      return;
    }
    Future.delayed(const Duration(milliseconds: 80), () {
      if (!scrollController.hasClients) {
        return;
      }
      final targetOffset = (index * 132.0).clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      );
      scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  List<FollowUser> _distinctFollowUsers(Iterable<FollowUser> items) {
    final result = <FollowUser>[];
    final seenIds = <String>{};
    for (final item in items) {
      final id = item.id.trim().isNotEmpty
          ? item.id.trim()
          : "${item.siteId}_${item.roomId}";
      if (seenIds.add(id)) {
        result.add(item);
      }
    }
    return result;
  }

  List<FollowGroupOption> get groupOptions {
    const options = <FollowGroupOption>[
      FollowGroupOption(id: "all", title: "全部"),
      FollowGroupOption(id: "live", title: "开播中", liveStatus: 2),
      FollowGroupOption(id: "not_live", title: "未开播", liveStatus: 1),
    ];
    return options;
  }

  List<FollowUser> _filterBySelectedGroup() {
    FollowGroupOption? selected;
    for (final option in groupOptions) {
      if (option.id == selectedGroupId.value) {
        selected = option;
        break;
      }
    }
    final source = _buildSelectedTagList();
    if (selected == null || selected.id == "all") {
      selectedGroupId.value = "all";
      return FollowService.instance.sortFollowUsers(
        _distinctFollowUsers(source),
      );
    }
    final liveStatus = selected.liveStatus;
    if (liveStatus != null) {
      final expectedStatus = liveStatus == 1 ? {0, 1} : {liveStatus};
      return FollowService.instance.sortFollowUsers(
        _distinctFollowUsers(
          source
              .where((item) => expectedStatus.contains(item.liveStatus.value)),
        ),
      );
    }
    return FollowService.instance.sortFollowUsers(
      _distinctFollowUsers(source),
    );
  }

  List<FollowUser> _buildFilteredList() {
    Iterable<FollowUser> items = _filterBySelectedGroup();
    if (AppSettingsController.instance.followOnlyLive.value) {
      items = items.where((item) => item.liveStatus.value == 2);
    }
    final keyword = searchKeyword.value.trim().toLowerCase();
    if (keyword.isNotEmpty) {
      items = items.where(
        (item) => item.userName.toLowerCase().contains(keyword),
      );
    }
    return FollowService.instance.sortFollowUsers(_distinctFollowUsers(items));
  }

  List<FollowUser> _buildSelectedTagList() {
    final source = FollowService.instance.followList;
    final selectedTag = selectedTagOption;
    if (selectedTag.id == allTagId) {
      return FollowService.instance.sortFollowUsers(
        _distinctFollowUsers(source),
      );
    }
    final memberIds = selectedTag.userId.toSet();
    return FollowService.instance.sortFollowUsers(
      _distinctFollowUsers(
        source.where(
          (item) => memberIds.contains(item.id) || item.tag == selectedTag.tag,
        ),
      ),
    );
  }

  void setSelectedTag(FollowUserTag tag) {
    selectedTagId.value = tag.id;
    currentDisplayPage.value = 1;
    filterData();
  }

  void setSearchKeyword(String value) {
    searchKeyword.value = value.trim();
    currentDisplayPage.value = 1;
    filterData();
  }

  void clearSearchKeyword() {
    if (searchKeyword.value.isEmpty) {
      return;
    }
    searchKeyword.value = "";
    currentDisplayPage.value = 1;
    filterData();
  }

  void _requestVisiblePreviews(List<FollowUser> items) {
    if (items.isEmpty ||
        !AppSettingsController.instance.followShowLiveCover.value) {
      return;
    }
    unawaited(FollowService.instance.refreshVisiblePreviews(items));
  }

  void setDisplayStyle(String value) {
    AppSettingsController.instance.setFollowDisplayStyle(value);
    filterData();
  }

  void setOnlyLive(bool value) {
    AppSettingsController.instance.setFollowOnlyLive(value);
    currentDisplayPage.value = 1;
    filterData();
  }

  void setRefreshOnEnter(bool value) {
    AppSettingsController.instance.setFollowRefreshOnEnter(value);
  }

  void setShowLiveCover(bool value) {
    AppSettingsController.instance.setFollowShowLiveCover(value);
    filterData();
  }

  void setGroupOption(FollowGroupOption option) {
    selectedGroupId.value = option.id;
    filterData();
  }

  void removeItem(FollowUser item) async {
    var result =
        await Utils.showAlertDialog("确定要取消关注${item.userName}吗?", title: "取消关注");
    if (!result) {
      return;
    }
    // 取消关注同时删除标签内的 userId
    if (item.tag != "全部") {
      var tag = tagList.firstWhere((tag) => tag.tag == item.tag);
      tag.userId.remove(item.id);
      updateTag(tag);
    }
    await DBService.instance.followBox.delete(item.id);
    refreshData();
  }

  void updateItem(FollowUser item) {
    FollowService.instance.addFollow(item);
  }

  bool isSelectedForMultiRoom(FollowUser item) {
    return selectedMultiRoomKeys.contains(item.id);
  }

  void toggleMultiSelectMode() {
    if (!PlatformUtils.supportsInlineMultiRoom) {
      return;
    }
    multiSelectMode.value = !multiSelectMode.value;
    if (!multiSelectMode.value) {
      selectedMultiRoomKeys.clear();
    }
  }

  void toggleMultiRoomItem(FollowUser item) {
    if (!PlatformUtils.supportsInlineMultiRoom) {
      return;
    }
    if (item.liveStatus.value != 2) {
      SmartDialog.showToast("只能选择直播中的关注");
      return;
    }
    if (selectedMultiRoomKeys.contains(item.id)) {
      selectedMultiRoomKeys.remove(item.id);
      return;
    }
    selectedMultiRoomKeys.add(item.id);
  }

  void openSelectedMultiRooms() async {
    if (!PlatformUtils.supportsInlineMultiRoom) {
      SmartDialog.showToast("当前移动端版本已关闭多开同屏");
      return;
    }
    final selected = list
        .where((item) =>
            selectedMultiRoomKeys.contains(item.id) &&
            item.liveStatus.value == 2 &&
            Sites.allSites.containsKey(item.siteId))
        .map(MultiRoomItem.fromFollow)
        .toList();
    if (selected.length < 2) {
      SmartDialog.showToast("至少选择 2 个直播中的关注");
      return;
    }
    if (await DesktopMultiWindowService.openRooms(selected)) {
      return;
    }
    AppNavigator.toMultiRoom(selected);
  }

  void toggleSpecialFollow(FollowUser item) async {
    await FollowService.instance.updateSpecialFollow(
      item,
      !item.isSpecialFollow,
    );
    filterData();
  }

  Future<void> openFollowRoom(FollowUser item) async {
    final resolved =
        await FollowService.instance.resolveFollowBeforeEnter(item);
    final site = Sites.allSites[resolved.siteId];
    if (site == null) {
      return;
    }
    AppNavigator.toLiveRoomDetail(
      site: site,
      roomId: resolved.roomId,
    );
  }

  // 修改item的标签
  void setItemTag(FollowUser item, FollowUserTag targetTag) {
    FollowUserTag tarTag = targetTag;
    FollowUserTag curTag = tagList.firstWhere((tag) => tag.tag == item.tag);
    // 从当前标签（非全部）删除item 向目标标签(全部包含所有item == 非全部)添加item
    curTag.userId.remove(item.id);
    tarTag.userId.addIf(!tarTag.userId.contains(item.id), item.id);
    // 数据库更新
    item.tag = tarTag.tag;
    updateTag(curTag);
    updateTag(tarTag);
    updateItem(item);
    filterData();
  }

  Future<void> removeTag(FollowUserTag tag) async {
    // 将tag下的所有follow设置为全部
    for (var i in tag.userId) {
      var follow = DBService.instance.followBox.get(i);
      if (follow != null) {
        follow.tag = "全部";
        updateItem(follow);
      }
    }
    await FollowService.instance.delFollowUserTag(tag);
    updateTagList();
    filterData();
    Log.i('删除tag${tag.tag}');
  }

  void addTag(String tag) async {
    FollowService.instance
        .addFollowUserTag(tag)
        .then((value) => updateTagList());
  }

  void updateTag(FollowUserTag followUserTag) {
    if (followUserTag.tag == '全部') {
      return;
    }
    FollowService.instance.updateFollowUserTag(followUserTag);
  }

  void updateTagName(FollowUserTag followUserTag, String newTagName) {
    // 未操作
    if (followUserTag.tag == newTagName) {
      return;
    }
    // 避免重名
    if (tagList.any((item) => item.tag == newTagName)) {
      SmartDialog.showToast("标签名重复，修改失败");
      return;
    }
    // 限制长度
    final String trimmedName = newTagName.trim();
    if (trimmedName.isEmpty) {
      SmartDialog.showToast("标签名不能为空，修改失败");
      return;
    }
    if (trimmedName.length > 8) {
      SmartDialog.showToast("标签名长度不能超过8个字符，修改失败");
      return;
    }
    final FollowUserTag newTag = followUserTag.copyWith(tag: trimmedName);
    updateTag(newTag);
    // update item's tag when update tagName
    for (var i in newTag.userId) {
      var follow = DBService.instance.followBox.get(i);
      if (follow != null) {
        follow.tag = trimmedName;
        updateItem(follow);
      }
    }
    SmartDialog.showToast("标签名修改成功");
    updateTagList();
    filterData();
  }

  // 调整标签顺序
  void updateTagOrder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1; // 处理索引调整
    final item = userTagList.removeAt(oldIndex);
    userTagList.insert(newIndex, item);
    tagList.value = tagList.take(3).toList();
    tagList.addAll(userTagList);
    DBService.instance.updateFollowTagOrder(userTagList);
  }

  @override
  void onClose() {
    onUpdatedIndexedStream?.cancel();
    onUpdatedListStream?.cancel();
    super.onClose();
  }
}
