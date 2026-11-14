import { useEffect, useRef, useState } from "react";
import {
  IconSearch,
  IconPlus,
  IconSettings,
  IconChevronDown,
  IconDots,
  IconDeviceDesktop,
  IconCircleCheck,
  IconCircleX,
  IconHelpCircle,
  IconX,
  IconChevronLeft,
  IconChevronRight,
  IconFolder,
  IconArrowRight,
  IconPencil,
  IconTrash,
  IconArrowBackUp,
} from "@tabler/icons-react";
import { initialGroups, makeDevices } from "./data";
import { normalizeDeviceAddress } from "./address";
const PAGE_SIZE = 12;
const Icon = ({ as: Component, ...props }) => (
  <Component size={22} stroke={1.8} aria-hidden="true" {...props} />
);
function Check({ checked, mixed = false, onChange, label }) {
  const ref = useRef(null);
  useEffect(() => {
    if (ref.current) ref.current.indeterminate = mixed;
  }, [mixed]);
  return (
    <input
      ref={ref}
      type="checkbox"
      checked={checked}
      onChange={onChange}
      aria-label={label}
    />
  );
}
function Modal({ title, close, children }) {
  const ref = useRef(null),
    previous = useRef(document.activeElement);
  useEffect(() => {
    const active = previous.current;
    ref.current.showModal();
    (
      ref.current.querySelector("input,select,textarea") ||
      ref.current.querySelector("button")
    )?.focus();
    return () => active?.focus();
  }, [title]);
  return (
    <dialog
      ref={ref}
      className="modal"
      aria-label={title}
      onCancel={(e) => {
        e.preventDefault();
        close();
      }}
      onClick={(e) => {
        if (e.target === ref.current) close();
      }}
    >
      <div className="modal-head">
        <h2>{title}</h2>
        <button className="icon-button" onClick={close} aria-label="关闭对话框">
          <Icon as={IconX} />
        </button>
      </div>
      {children}
    </dialog>
  );
}
export function App() {
  const [groups, setGroups] = useState(initialGroups),
    [devices, setDevices] = useState(makeDevices);
  const [group, setGroup] = useState("all"),
    [groupSearch, setGroupSearch] = useState(""),
    [query, setQuery] = useState(""),
    [status, setStatus] = useState("全部状态"),
    [source, setSource] = useState("收藏");
  const [selected, setSelected] = useState(
      new Set(["device-0", "device-1", "device-5"]),
    ),
    [page, setPage] = useState(0);
  const [modal, setModal] = useState(null),
    [menu, setMenu] = useState(null),
    [name, setName] = useState(""),
    [address, setAddress] = useState(""),
    [autoUpdateAddress, setAutoUpdateAddress] = useState(true),
    [error, setError] = useState("");
  const [destination, setDestination] = useState(""),
    [destinationSearch, setDestinationSearch] = useState(""),
    [toast, setToast] = useState(null),
    [undo, setUndo] = useState(null);
  const groupName = (id) => groups.find((g) => g.id === id)?.name || "未分组";
  const groupTitle = group === "all" ? "全部收藏" : groupName(group);
  const count = (id) =>
    devices.filter((d) => id === "all" || d.group === id).length;
  const base = devices.filter(
    (d) =>
      source === "收藏" ||
      (source === "附近设备"
        ? d.status === "可达"
        : Number(d.id.split("-")[1]) < 18),
  );
  const scoped = base.filter(
    (d) => source !== "收藏" || group === "all" || d.group === group,
  );
  const filtered = scoped.filter(
    (d) =>
      `${d.name} ${d.address} ${d.note}`
        .toLowerCase()
        .includes(query.trim().toLowerCase()) &&
      (status === "全部状态" || status === d.status),
  );
  const maxPage = Math.max(0, Math.ceil(filtered.length / PAGE_SIZE) - 1),
    currentPage = Math.min(page, maxPage);
  const visible = filtered.slice(
    currentPage * PAGE_SIZE,
    (currentPage + 1) * PAGE_SIZE,
  );
  const allChecked =
    visible.length > 0 && visible.every((d) => selected.has(d.id));
  const destinations = [{ id: "", name: "未分组" }, ...groups].filter((g) =>
    g.name.includes(destinationSearch.trim()),
  );
  useEffect(() => {
    const handler = (e) => {
      if (e.key === "Escape") setMenu(null);
    };
    window.addEventListener("keydown", handler);
    return () => window.removeEventListener("keydown", handler);
  }, []);
  function notify(message, canUndo = false) {
    setToast(message);
    if (!canUndo) setUndo(null);
  }
  function snapshot() {
    setUndo({ groups, devices, group });
  }
  function chooseGroup(id) {
    setGroup(id);
    setSource("收藏");
    setQuery("");
    setPage(0);
    setSelected(new Set());
    setMenu(null);
  }
  function changeSource(value) {
    setSource(value);
    setSelected(new Set());
    setQuery("");
    setPage(0);
    setMenu(null);
  }
  function toggle(id) {
    setSelected((old) => {
      const next = new Set(old);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }
  function toggleVisible() {
    setSelected((old) => {
      const next = new Set(old);
      visible.forEach((d) => (allChecked ? next.delete(d.id) : next.add(d.id)));
      return next;
    });
  }
  function open(type, data = {}) {
    setModal({ type, ...data });
    setMenu(null);
    setError("");
    setName(data.name || "");
    setAddress(type === "edit-address" ? data.device.address : "");
    setAutoUpdateAddress(data.device?.autoUpdateAddress !== false);
    setDestination("");
    setDestinationSearch("");
  }
  function submitName(e) {
    e.preventDefault();
    const value = name.trim();
    if (!value) return setError("请输入分组名称");
    if ([...value].length > 32) return setError("分组名称最多 32 个字符");
    if (
      groups.some(
        (g) =>
          g.id !== modal.id && g.name.toLowerCase() === value.toLowerCase(),
      ) ||
      ["未分组", "全部收藏"].includes(value)
    )
      return setError("已存在同名分组，请换一个名称");
    snapshot();
    if (modal.type === "rename")
      setGroups((old) =>
        old.map((g) => (g.id === modal.id ? { ...g, name: value } : g)),
      );
    else
      setGroups((old) => [...old, { id: `group-${Date.now()}`, name: value }]);
    notify(
      modal.type === "rename" ? `已重命名为“${value}”` : `已新建分组“${value}”`,
      true,
    );
    setModal(null);
  }
  function saveAddress(e) {
    e.preventDefault();
    const value = normalizeDeviceAddress(address);
    if (!value) return setError("请输入有效的 IPv4、IPv6 或主机名，不含端口");
    if (
      devices.some(
        (d) =>
          d.id !== modal.device.id &&
          normalizeDeviceAddress(d.address) === value,
      )
    )
      return setError("该地址已被另一台设备使用，请核对地址或编辑已有设备");
    const changed = value !== modal.device.address;
    if (
      !changed &&
      autoUpdateAddress === (modal.device.autoUpdateAddress !== false)
    ) {
      setModal({ type: "device", device: modal.device });
      return;
    }
    snapshot();
    const updated = {
      ...modal.device,
      address: value,
      autoUpdateAddress,
      ...(changed ? { status: "未检查", addressSource: "手动修改" } : {}),
    };
    setDevices((old) => old.map((d) => (d.id === updated.id ? updated : d)));
    setModal({ type: "device", device: updated });
    notify(
      changed
        ? `已更新“${updated.name}”的地址，尚未检查可达性`
        : "已更新地址自动更新设置",
      true,
    );
  }
  function move() {
    const targets = modal.ids || [...selected],
      changing = devices.filter(
        (d) => targets.includes(d.id) && d.group !== destination,
      );
    if (!changing.length) return setError("所选设备已在此分组中");
    snapshot();
    setDevices((old) =>
      old.map((d) =>
        targets.includes(d.id) ? { ...d, group: destination } : d,
      ),
    );
    setSelected(new Set());
    setModal(null);
    notify(
      `已将 ${changing.length} 台设备移到“${groupName(destination)}”`,
      true,
    );
  }
  function deleteGroup() {
    snapshot();
    setDevices((old) =>
      old.map((d) => (d.group === modal.id ? { ...d, group: "" } : d)),
    );
    setGroups((old) => old.filter((g) => g.id !== modal.id));
    if (group === modal.id) setGroup("");
    setSelected(new Set());
    setModal(null);
    notify(`已删除分组“${modal.name}”，设备已保留在“未分组”`, true);
  }
  function restore() {
    setDevices(undo.devices);
    setGroups(undo.groups);
    setGroup(undo.group);
    setSelected(new Set());
    setUndo(null);
    setToast("已撤销上次操作");
  }
  const groupEntry = (id, label) => (
    <div key={id} className={`group-entry ${group === id ? "active" : ""}`}>
      <button
        className="group-choice"
        onClick={() => chooseGroup(id)}
        aria-current={group === id ? "true" : undefined}
        title={label}
      >
        <span>{label}</span>
        <span className="count">{count(id)}</span>
      </button>
      {id && id !== "all" && (
        <button
          className="group-menu icon-button"
          aria-label={`管理分组 ${label}`}
          onClick={() =>
            setMenu(menu?.id === id ? null : { type: "group", id })
          }
        >
          <Icon as={IconDots} size={19} />
        </button>
      )}
      {menu?.type === "group" && menu.id === id && (
        <div className="menu" role="menu" aria-label={`管理 ${label}`}>
          <button
            role="menuitem"
            onClick={() => open("rename", { id, name: label })}
          >
            <Icon as={IconPencil} size={18} />
            重命名分组
          </button>
          <button
            role="menuitem"
            className="danger"
            onClick={() => open("delete", { id, name: label })}
          >
            <Icon as={IconTrash} size={18} />
            删除分组
          </button>
        </div>
      )}
    </div>
  );
  return (
    <div className="app-shell">
      <header className="app-header">
        <a
          className="brand"
          href="#"
          onClick={(e) => {
            e.preventDefault();
            chooseGroup("all");
          }}
        >
          <img src="/assets/subnetdesk-mark.png" alt="" />
          <span>SubnetDesk</span>
        </a>
        <nav aria-label="主导航">
          <button
            onClick={() => notify("此原型聚焦设备分组；首页沿用现有设计")}
          >
            首页
          </button>
          <button className="active" aria-current="page">
            设备列表
          </button>
          <button onClick={() => notify("本机配置沿用现有设计")}>本机</button>
        </nav>
        <div className="header-actions">
          <button
            className="icon-button"
            aria-label="添加设备"
            onClick={() => open("add")}
          >
            <Icon as={IconPlus} size={28} />
          </button>
          <button
            className="icon-button"
            aria-label="设置"
            onClick={() => notify("设置沿用现有设计")}
          >
            <Icon as={IconSettings} size={29} />
          </button>
        </div>
      </header>
      <div className="workspace">
        <aside className="sidebar" aria-label="收藏分组">
          <div className="sidebar-heading">
            <h2>分组</h2>
            <button className="text-button" onClick={() => open("create")}>
              <Icon as={IconPlus} size={19} />
              新建分组
            </button>
          </div>
          <label className="search group-search">
            <Icon as={IconSearch} />
            <input
              value={groupSearch}
              onChange={(e) => setGroupSearch(e.target.value)}
              placeholder="搜索分组"
              aria-label="搜索分组"
            />
          </label>
          <div className="fixed-groups">
            {groupEntry("all", "全部收藏")}
            {groupEntry("", "未分组")}
          </div>
          <div className="custom-groups">
            {groups
              .filter((g) => g.name.includes(groupSearch.trim()))
              .map((g) => groupEntry(g.id, g.name))}
            {!groups.some((g) => g.name.includes(groupSearch.trim())) && (
              <p className="muted small">没有匹配的分组</p>
            )}
          </div>
          <div className="prototype-note">交互原型 · 示例设备</div>
        </aside>
        <main>
          <div className="source-tabs" role="tablist" aria-label="设备来源">
            {["附近设备", "最近连接", "收藏"].map((tab) => (
              <button
                key={tab}
                role="tab"
                aria-selected={source === tab}
                className={source === tab ? "active" : ""}
                onClick={() => changeSource(tab)}
              >
                {tab}
              </button>
            ))}
          </div>
          <h1>
            {source === "收藏"
              ? group === "all"
                ? "收藏设备"
                : groupName(group)
              : source}
            <span>{scoped.length} 台</span>
          </h1>
          <div className="toolbar">
            <label className="search device-search">
              <Icon as={IconSearch} />
              <input
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setPage(0);
                  setSelected(new Set());
                }}
                placeholder={`搜索${source === "收藏" ? groupTitle : source}：名称、IP、备注`}
                aria-label="搜索设备"
              />
              {query && (
                <button
                  className="icon-button clear"
                  aria-label="清空搜索"
                  onClick={() => {
                    setQuery("");
                    setPage(0);
                  }}
                >
                  <Icon as={IconX} size={17} />
                </button>
              )}
            </label>
            <label className="select-wrap">
              <select
                aria-label="设备状态"
                value={status}
                onChange={(e) => {
                  setStatus(e.target.value);
                  setPage(0);
                  setSelected(new Set());
                }}
              >
                {["全部状态", "可达", "暂不可达", "未检查"].map((s) => (
                  <option key={s}>{s}</option>
                ))}
              </select>
              <Icon as={IconChevronDown} />
            </label>
            <button className="primary add-button" onClick={() => open("add")}>
              <Icon as={IconPlus} />
              添加设备
            </button>
          </div>
          {selected.size > 0 ? (
            <div className="selection-bar">
              <strong>已选 {selected.size} 台</strong>
              <button
                className="primary move-button"
                onClick={() => open("move")}
              >
                移动到分组
                <Icon as={IconChevronDown} size={18} />
              </button>
              <button
                className="text-button muted"
                onClick={() => setSelected(new Set())}
              >
                取消选择
              </button>
            </div>
          ) : (
            <div className="scope-line">
              <span>
                {source === "收藏" ? groupTitle : source}
                {query && ` · “${query}”的搜索结果`}
              </span>
              <span>{filtered.length} 台设备</span>
            </div>
          )}
          <div
            className="table-container"
            tabIndex={0}
            role="region"
            aria-label="设备表格"
          >
            <table>
              <thead>
                <tr>
                  <th className="check-cell">
                    <Check
                      checked={allChecked}
                      mixed={
                        !allChecked && visible.some((d) => selected.has(d.id))
                      }
                      onChange={toggleVisible}
                      label={`选择本页 ${visible.length} 台设备`}
                    />
                  </th>
                  <th>设备名称</th>
                  <th>地址</th>
                  <th>所属分组</th>
                  <th>状态</th>
                  <th>操作</th>
                </tr>
              </thead>
              <tbody>
                {visible.map((device) => (
                  <tr
                    key={device.id}
                    className={selected.has(device.id) ? "selected" : ""}
                  >
                    <td className="check-cell">
                      <Check
                        label={`选择 ${device.name}`}
                        checked={selected.has(device.id)}
                        onChange={() => toggle(device.id)}
                      />
                    </td>
                    <td>
                      <div className="device-name">
                        <Icon as={IconDeviceDesktop} size={24} />
                        <span title={`${device.name} · ${device.platform}`}>
                          {device.name}
                        </span>
                      </div>
                    </td>
                    <td className="address">{device.address}</td>
                    <td>
                      <span
                        className="cell-text"
                        title={groupName(device.group)}
                      >
                        {groupName(device.group)}
                      </span>
                    </td>
                    <td>
                      <span
                        className={`status ${device.status === "可达" ? "reachable" : device.status === "未检查" ? "unchecked" : "unreachable"}`}
                      >
                        <Icon
                          as={
                            device.status === "可达"
                              ? IconCircleCheck
                              : device.status === "未检查"
                                ? IconHelpCircle
                                : IconCircleX
                          }
                          size={23}
                        />
                        {device.status}
                      </span>
                    </td>
                    <td>
                      <div className="row-actions">
                        <button
                          className="connect"
                          onClick={() => open("connect", { device })}
                          aria-label={`连接 ${device.name}`}
                        >
                          连接
                        </button>
                        <button
                          className="icon-button"
                          aria-label={`更多操作 ${device.name}`}
                          onClick={() => open("device", { device })}
                        >
                          <Icon as={IconDots} />
                        </button>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
            {!filtered.length && (
              <div className="empty">
                <Icon as={IconSearch} size={34} />
                <h2>没有找到设备</h2>
                <p>
                  {query
                    ? "试试其他名称、IP 或备注。"
                    : "这个范围内暂时没有设备。"}
                </p>
                {group !== "all" && (
                  <button
                    className="secondary"
                    onClick={() => {
                      setGroup("all");
                      setPage(0);
                    }}
                  >
                    在全部收藏中查找
                  </button>
                )}
                <button
                  className="text-button"
                  onClick={() => {
                    setQuery("");
                    setStatus("全部状态");
                  }}
                >
                  清除筛选
                </button>
              </div>
            )}
          </div>
          <footer className="table-footer">
            <span>
              {filtered.length
                ? `显示 ${currentPage * PAGE_SIZE + 1}–${Math.min((currentPage + 1) * PAGE_SIZE, filtered.length)} / 共 ${filtered.length} 台`
                : "共 0 台"}
              {selected.size > 0 && (
                <span className="selected-note">
                  {" "}
                  · 已选 {selected.size} 台
                </span>
              )}
            </span>
            <div className="pagination">
              <button
                className="icon-button"
                disabled={currentPage === 0}
                aria-label="上一页"
                onClick={() => setPage(currentPage - 1)}
              >
                <Icon as={IconChevronLeft} />
              </button>
              <span>
                {currentPage + 1} / {maxPage + 1}
              </span>
              <button
                className="icon-button"
                disabled={currentPage === maxPage}
                aria-label="下一页"
                onClick={() => setPage(currentPage + 1)}
              >
                <Icon as={IconChevronRight} />
              </button>
            </div>
          </footer>
        </main>
      </div>
      {menu && <div className="menu-dismiss" onClick={() => setMenu(null)} />}
      {toast && (
        <div className="toast" role="status">
          <span>{toast}</span>
          {undo && (
            <button className="text-button" onClick={restore}>
              <Icon as={IconArrowBackUp} size={18} />
              撤销
            </button>
          )}
          <button
            className="icon-button"
            aria-label="关闭提示"
            onClick={() => {
              setToast(null);
              setUndo(null);
            }}
          >
            <Icon as={IconX} size={18} />
          </button>
        </div>
      )}
      {modal && (
        <Modal
          title={
            {
              create: "新建分组",
              rename: "重命名分组",
              delete: "删除分组",
              move: "移动到分组",
              add: "添加设备",
              "edit-address": "编辑地址",
              connect: "连接设备",
              device: "设备详情",
            }[modal.type]
          }
          close={() => setModal(null)}
        >
          {["create", "rename"].includes(modal.type) && (
            <form onSubmit={submitName}>
              <label className="field">
                分组名称
                <input
                  autoFocus
                  value={name}
                  onChange={(e) => {
                    setName(e.target.value);
                    setError("");
                  }}
                  placeholder="例如：上海办公室"
                />
              </label>
              <p className="muted small">最多 32 个字符，名称不能重复。</p>
              {error && (
                <p className="error" role="alert">
                  {error}
                </p>
              )}
              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary"
                  onClick={() => setModal(null)}
                >
                  取消
                </button>
                <button className="primary" type="submit">
                  {modal.type === "create" ? "创建分组" : "保存名称"}
                </button>
              </div>
            </form>
          )}
          {modal.type === "delete" && (
            <>
              <p>
                删除“{modal.name}”后，组内 {count(modal.id)}{" "}
                台设备将移到“未分组”。
              </p>
              <p className="muted">
                设备、连接凭据与连接历史会保留，此操作可撤销。
              </p>
              <div className="modal-actions">
                <button className="secondary" onClick={() => setModal(null)}>
                  取消
                </button>
                <button className="danger-button" onClick={deleteGroup}>
                  删除分组
                </button>
              </div>
            </>
          )}
          {modal.type === "move" && (
            <>
              <p className="muted">
                已选择 {(modal.ids || [...selected]).length}{" "}
                台设备。每台设备只属于一个分组。
              </p>
              <label className="search">
                <Icon as={IconSearch} />
                <input
                  autoFocus
                  value={destinationSearch}
                  onChange={(e) => setDestinationSearch(e.target.value)}
                  placeholder="搜索目标分组"
                  aria-label="搜索目标分组"
                />
              </label>
              <div className="destinations">
                {destinations.map((g) => (
                  <label
                    key={g.id}
                    className={
                      destination === g.id
                        ? "destination active"
                        : "destination"
                    }
                  >
                    <input
                      type="radio"
                      name="destination"
                      checked={destination === g.id}
                      onChange={() => {
                        setDestination(g.id);
                        setError("");
                      }}
                      value={g.id}
                    />
                    <Icon as={IconFolder} size={20} />
                    <span>{g.name}</span>
                    <span className="muted">{count(g.id)}</span>
                  </label>
                ))}
                {!destinations.length && (
                  <p className="muted">没有匹配的分组，请换一个名称。</p>
                )}
              </div>
              <div className="move-preview">
                <span>目标分组</span>
                <strong>{groupName(destination)}</strong>
                <span>
                  {count(destination)} <Icon as={IconArrowRight} size={16} />{" "}
                  {count(destination) +
                    devices.filter(
                      (d) =>
                        (modal.ids || [...selected]).includes(d.id) &&
                        d.group !== destination,
                    ).length}{" "}
                  台
                </span>
              </div>
              {error && (
                <p className="error" role="alert">
                  {error}
                </p>
              )}
              <div className="modal-actions">
                <button className="secondary" onClick={() => setModal(null)}>
                  取消
                </button>
                <button className="primary" onClick={move}>
                  移动 {(modal.ids || [...selected]).length} 台设备
                </button>
              </div>
              <p className="small muted">移动后可撤销。</p>
            </>
          )}
          {modal.type === "add" && (
            <form
              onSubmit={(e) => {
                e.preventDefault();
                const value = normalizeDeviceAddress(address);
                if (!value)
                  return setError("请输入有效的 IPv4、IPv6 或主机名，不含端口");
                if (
                  devices.some(
                    (d) => normalizeDeviceAddress(d.address) === value,
                  )
                )
                  return setError("该地址已在设备列表中");
                snapshot();
                setDevices((old) => [
                  ...old,
                  {
                    id: `device-${Date.now()}`,
                    name: name.trim() || value,
                    address: value,
                    group: group === "all" ? "" : group,
                    status: "未检查",
                    platform: "未知",
                    note: "",
                  },
                ]);
                setModal(null);
                notify("已添加示例设备，尚未检查可达性", true);
              }}
            >
              <label className="field">
                IP 或主机名
                <input
                  autoFocus
                  value={address}
                  onChange={(e) => {
                    setAddress(e.target.value);
                    setError("");
                  }}
                  placeholder="例如 10.10.1.80"
                />
              </label>
              <label className="field">
                设备名称（可选）
                <input
                  value={name}
                  onChange={(e) => setName(e.target.value)}
                  placeholder="例如：会议室电脑"
                />
              </label>
              <p className="muted small">
                保存到：{group === "all" ? "未分组" : groupName(group)}
              </p>
              {error && (
                <p className="error" role="alert">
                  {error}
                </p>
              )}
              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary"
                  onClick={() => setModal(null)}
                >
                  取消
                </button>
                <button className="primary" type="submit">
                  添加设备
                </button>
              </div>
            </form>
          )}
          {modal.type === "edit-address" && (
            <form onSubmit={saveAddress}>
              <div className="address-context">
                <strong>{modal.device.name}</strong>
                <span className="muted">{groupName(modal.device.group)}</span>
              </div>
              <p className="muted small">当前地址：{modal.device.address}</p>
              <label className="field">
                新地址
                <input
                  autoFocus
                  value={address}
                  onChange={(e) => {
                    setAddress(e.target.value);
                    setError("");
                  }}
                  placeholder="IPv4、IPv6 或主机名"
                  aria-describedby="address-help"
                  aria-invalid={Boolean(error)}
                />
              </label>
              <p id="address-help" className="muted small">
                修改后保留设备名称和分组，可达状态重新检查。连接时继续核对设备身份。
              </p>
              <label className="address-setting">
                <input
                  type="checkbox"
                  checked={autoUpdateAddress}
                  onChange={(e) => setAutoUpdateAddress(e.target.checked)}
                />
                <span>允许 mDNS 自动更新地址</span>
              </label>
              <p className="muted small">
                {autoUpdateAddress
                  ? "发现同一设备的新地址时自动更新；手动保存后仍保持开启。"
                  : "已关闭自动更新，后续保留手动填写的地址。"}
              </p>
              {error && (
                <p className="error" role="alert">
                  {error}
                </p>
              )}
              <div className="modal-actions">
                <button
                  type="button"
                  className="secondary"
                  onClick={() =>
                    setModal({ type: "device", device: modal.device })
                  }
                >
                  取消
                </button>
                <button type="submit" className="primary">
                  保存地址
                </button>
              </div>
            </form>
          )}
          {["connect", "device"].includes(modal.type) && (
            <>
              <div className="detail-title">
                <Icon as={IconDeviceDesktop} size={38} />
                <div>
                  <h3>{modal.device.name}</h3>
                  <p className="muted">
                    {modal.type === "connect" && `${modal.device.address} · `}
                    {modal.device.platform}
                  </p>
                </div>
              </div>
              {modal.type === "connect" ? (
                <>
                  <p>
                    这是分组交互原型。正式应用将继续进行设备身份核对与认证。
                  </p>
                  <p className="muted">
                    当前设备状态：{modal.device.status}
                    。此处不会发起真实远程连接。
                  </p>
                  <div className="modal-actions">
                    <button className="primary" onClick={() => setModal(null)}>
                      返回设备列表
                    </button>
                  </div>
                </>
              ) : (
                <>
                  <dl>
                    <dt>连接地址</dt>
                    <dd className="address-value">
                      <span>{modal.device.address}</span>
                      <button
                        className="text-button"
                        onClick={() =>
                          open("edit-address", { device: modal.device })
                        }
                      >
                        <Icon as={IconPencil} size={17} />
                        编辑地址
                      </button>
                    </dd>
                    <dt>地址来源</dt>
                    <dd>{modal.device.addressSource || "已保存"}</dd>
                    <dt>自动更新</dt>
                    <dd>
                      {modal.device.autoUpdateAddress !== false
                        ? "mDNS 发现同一设备时更新"
                        : "已关闭，使用手动地址"}
                    </dd>
                    <dt>所属分组</dt>
                    <dd>{groupName(modal.device.group)}</dd>
                    <dt>状态</dt>
                    <dd>{modal.device.status}</dd>
                    <dt>备注</dt>
                    <dd>{modal.device.note || "暂无备注"}</dd>
                  </dl>
                  <div className="modal-actions">
                    <button
                      className="secondary"
                      onClick={() => open("move", { ids: [modal.device.id] })}
                    >
                      移动到分组
                    </button>
                    <button
                      className="primary"
                      onClick={() => open("connect", { device: modal.device })}
                    >
                      连接设备
                    </button>
                  </div>
                </>
              )}
            </>
          )}
        </Modal>
      )}
    </div>
  );
}
