// SPDX-License-Identifier: GPL-3.0-or-later
#pragma once

#include <QString>

namespace gallery::core {

// 按 XDG 规范把文件移入 ~/.local/share/Trash（files + info/.trashinfo）。
// 绝不直接 unlink；失败时返回 false 并写入 error。
bool moveToTrash(const QString &filePath, QString *error = nullptr);

} // namespace gallery::core
