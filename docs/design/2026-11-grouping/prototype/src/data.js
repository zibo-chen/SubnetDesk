export const initialGroups = [
  { id: "sh", name: "上海办公室" },
  { id: "bj", name: "北京办公室" },
  { id: "sz", name: "深圳办公室" },
  { id: "test", name: "测试设备" },
  { id: "server", name: "服务器" },
];
const firstRows = [
  ["上海前台-01", "10.10.1.21", "sh", "可达"],
  ["上海设计-02", "10.10.1.22", "sh", "可达"],
  ["上海会议室-03", "10.10.1.23", "sh", "可达"],
  ["北京财务-01", "10.20.1.31", "bj", "暂不可达"],
  ["北京前台-02", "10.20.1.32", "bj", "可达"],
  ["深圳会议室", "10.30.1.12", "sz", "可达"],
  ["深圳设计-01", "10.30.1.13", "sz", "可达"],
  ["测试-Windows-03", "10.40.1.13", "test", "未检查"],
  ["测试-Linux-04", "10.40.1.14", "test", "可达"],
  ["文件服务器", "10.50.1.10", "server", "可达"],
  ["数据库服务器", "10.50.1.11", "server", "可达"],
  ["备份服务器", "10.50.1.12", "server", "可达"],
];
export function makeDevices() {
  const devices = firstRows.map(([name, address, group, status], i) => ({
    id: `device-${i}`,
    name,
    address,
    group,
    status,
    note: "",
    platform: "Windows",
  }));
  const totals = [24, 18, 16, 14, 12, 12];
  [...initialGroups, { id: "", name: "待整理设备" }].forEach((g, index) => {
    const existing = devices.filter((d) => d.group === g.id).length;
    for (let i = existing; i < totals[index]; i++)
      devices.push({
        id: `device-${devices.length}`,
        name: `${g.name}-${String(i + 1).padStart(2, "0")}`,
        address: `10.${(index + 1) * 10}.1.${60 + i}`,
        group: g.id,
        status: i % 7 === 0 ? "未检查" : i % 5 === 0 ? "暂不可达" : "可达",
        note: i % 3 === 0 ? "会议室备用" : "日常办公",
        platform: index === 4 ? "Linux" : i % 4 === 0 ? "macOS" : "Windows",
      });
  });
  return devices;
}
