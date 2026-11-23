# -*- coding: utf-8 -*-
# This script exports animations from iClone the lightest way possible.
# Comes with useful options like removing the root and t-pose first frame.




"""
CloneFBX – one-click avatar FBX exporter with option dialog
Adds a menu entry: Plugins ▶ CloneTools ▶ CloneFBX
"""

# ───────── Reallusion plugin handshake (kills the compatibility nag) ─────────
rl_plugin_info = {"ap": "iClone", "ap_version": "8.0"}  # iClone 8.x

# ───────── Imports ─────────
import os, tempfile, sys, subprocess, shlex, math, struct, zlib
import RLPy
from PySide2 import QtWidgets, QtCore
from shiboken2 import wrapInstance


def _sanitize_affix(text):
    s = str(text or "").strip()
    for ch in ("|", ";", ",", "\r", "\n"):
        s = s.replace(ch, "_")
    return s


# ───────── PRESETS ─────────
# Character Studio: motion-only clips. Root motion is kept and
# baked onto Genesis9 (RL_BoneRoot merged), Z up, Genesis 9 bone names, no T-pose frame.
PRESET_STUDIO, PRESET_UNREAL, PRESET_CUSTOM = "Character Studio", "Unreal Engine", "Custom"
_last_preset = PRESET_STUDIO  # the dialog opens on the last one used while iClone runs


# ───────── FBX OPTION DIALOG ─────────
class ExportOptionsDialog(QtWidgets.QDialog):
    """Preset selector + manual overrides → RLPy FBX option bitmasks"""
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("FBX Export Options")
        self.setWindowFlags(self.windowFlags() | QtCore.Qt.WindowStaysOnTopHint)

        vbox = QtWidgets.QVBoxLayout(self)

        # Preset selector
        preset_label = QtWidgets.QLabel("Preset:")
        vbox.addWidget(preset_label)
        self.combo_preset = QtWidgets.QComboBox()
        self.combo_preset.addItems([PRESET_STUDIO, PRESET_UNREAL, PRESET_CUSTOM])
        self.combo_preset.setCurrentText(_last_preset)
        vbox.addWidget(self.combo_preset)

        # Separator
        line0 = QtWidgets.QFrame()
        line0.setFrameShape(QtWidgets.QFrame.HLine)
        line0.setFrameShadow(QtWidgets.QFrame.Sunken)
        vbox.addWidget(line0)

        # Export options checkboxes
        self.chk_root_motion   = QtWidgets.QCheckBox("Export Root Motion")
        self.chk_zero_root     = QtWidgets.QCheckBox("Zero Motion Root")
        self.chk_remove_mesh   = QtWidgets.QCheckBox("Remove All Mesh")
        self.chk_tpose_first   = QtWidgets.QCheckBox("T-Pose on Motion First Frame")
        self.chk_remove_root   = QtWidgets.QCheckBox("Remove Bone Root")
        self.chk_remove_root.setToolTip(
            "Bakes RL_BoneRoot (and its root motion) into the child bone, "
            "e.g. Genesis9, then deletes RL_BoneRoot from the FBX.")
        self.chk_lightwave_yup = QtWidgets.QCheckBox("LightWave Y Up")
        self.chk_root_motion.setChecked(True)

        self._custom_widgets = []
        for w in (self.chk_root_motion, self.chk_zero_root,
                  self.chk_remove_mesh, self.chk_tpose_first,
                  self.chk_remove_root, self.chk_lightwave_yup):
            vbox.addWidget(w)
            self._custom_widgets.append(w)

        # Separator
        line1 = QtWidgets.QFrame()
        line1.setFrameShape(QtWidgets.QFrame.HLine)
        line1.setFrameShadow(QtWidgets.QFrame.Sunken)
        vbox.addWidget(line1)

        # Up Axis selection (opt2)
        self.axis_label = QtWidgets.QLabel("Up Axis (opt2):")
        vbox.addWidget(self.axis_label)

        self.radio_none = QtWidgets.QRadioButton("None (Z Up default)")
        self.radio_xup  = QtWidgets.QRadioButton("X Up")
        self.radio_yup  = QtWidgets.QRadioButton("Y Up")
        self.radio_ue4  = QtWidgets.QRadioButton("Unreal Engine 4 Bone Axis")
        self.radio_none.setChecked(True)

        axis_group = QtWidgets.QButtonGroup(self)
        for r in (self.radio_none, self.radio_xup, self.radio_yup, self.radio_ue4):
            axis_group.addButton(r)
            vbox.addWidget(r)
            self._custom_widgets.append(r)
        self._custom_widgets.append(self.axis_label)

        self.lbl_prefix = QtWidgets.QLabel("Name Prefix (optional):")
        self.txt_prefix = QtWidgets.QLineEdit()
        self.txt_prefix.setPlaceholderText("e.g. CharA_")
        self.lbl_suffix = QtWidgets.QLabel("Name Suffix (optional):")
        self.txt_suffix = QtWidgets.QLineEdit()
        self.txt_suffix.setPlaceholderText("e.g. _A")
        vbox.addWidget(self.lbl_prefix)
        vbox.addWidget(self.txt_prefix)
        vbox.addWidget(self.lbl_suffix)
        vbox.addWidget(self.txt_suffix)
        self._custom_widgets.append(self.lbl_prefix)
        self._custom_widgets.append(self.txt_prefix)
        self._custom_widgets.append(self.lbl_suffix)
        self._custom_widgets.append(self.txt_suffix)

        btns = QtWidgets.QDialogButtonBox(
            QtWidgets.QDialogButtonBox.Ok | QtWidgets.QDialogButtonBox.Cancel,
            QtCore.Qt.Horizontal, self)
        btns.accepted.connect(self.accept)
        btns.rejected.connect(self.reject)
        vbox.addWidget(btns)

        self.combo_preset.currentIndexChanged.connect(self._on_preset_changed)
        self._on_preset_changed(0)  # apply the starting preset

    # ── preset handling ──
    def preset(self):
        return self.combo_preset.currentText()

    def merges_root(self):
        """RL_BoneRoot is baked into Genesis9 after export (merge_bone_root)."""
        return self.preset() == PRESET_STUDIO or (self.preset() == PRESET_CUSTOM and self.chk_remove_root.isChecked())

    def _on_preset_changed(self, _idx):
        preset = self.preset()
        if preset == PRESET_STUDIO:
            # show what the preset exports; the boxes are locked below
            for chk, on in ((self.chk_root_motion, True), (self.chk_zero_root, False),
                            (self.chk_remove_mesh, True), (self.chk_tpose_first, False),
                            (self.chk_remove_root, True), (self.chk_lightwave_yup, False)):
                chk.setChecked(on)
            self.radio_none.setChecked(True)
            self.txt_prefix.clear()
            self.txt_suffix.clear()
        for w in self._custom_widgets:
            w.setEnabled(preset == PRESET_CUSTOM)
        # Remove All Mesh stays usable with the Unreal preset
        if preset == PRESET_UNREAL:
            self.chk_remove_mesh.setEnabled(True)

    # ── bitmask builders ──
    def options_bitmask(self):
        if self.preset() == PRESET_STUDIO:
            return RLPy.EExportFbxOptions_ExportRootMotion | RLPy.EExportFbxOptions_RemoveAllMesh
        if self.preset() == PRESET_UNREAL:
            flags = (RLPy.EExportFbxOptions_AutoSkinRigidMesh
                     | RLPy.EExportFbxOptions_ExportRootMotion
                     | RLPy.EExportFbxOptions_ZeroMotionRoot
                     | RLPy.EExportFbxOptions_ExportPbrTextureAsImageInFormatDirectory
                     | RLPy.EExportFbxOptions_InverseNormalY)
            if self.chk_remove_mesh.isChecked():
                flags |= RLPy.EExportFbxOptions_RemoveAllMesh
            return flags
        flags = 0
        if self.chk_root_motion.isChecked():
            flags |= RLPy.EExportFbxOptions_ExportRootMotion
        if self.chk_zero_root.isChecked():
            flags |= RLPy.EExportFbxOptions_ZeroMotionRoot
        if self.chk_remove_mesh.isChecked():
            flags |= RLPy.EExportFbxOptions_RemoveAllMesh
        if self.chk_tpose_first.isChecked():
            flags |= RLPy.EExportFbxOptions_TPoseOnMotionFirstFrame
        # Remove Bone Root is not an export flag: EExportFbxOptions_RemoveBoneRoot
        # makes ExportFbxFile fail, so the root is merged after export instead.
        if self.chk_lightwave_yup.isChecked():
            flags |= RLPy.EExportFbxOptions_LightWaveYUp
        return flags

    def get_up_axis_opt2(self):
        if self.preset() == PRESET_STUDIO:
            # Z up (the default), bone names untouched: the runtime binds clips by Genesis 9 name
            return RLPy.EExportFbxOptions2_ResetBoneScale
        prefix = _sanitize_affix(self.txt_prefix.text())
        suffix = _sanitize_affix(self.txt_suffix.text())
        if self.preset() == PRESET_UNREAL:
            flags = (RLPy.EExportFbxOptions2_UnrealEngine4BoneAxis
                     | RLPy.EExportFbxOptions2_RenameDuplicateBoneName
                     | RLPy.EExportFbxOptions2_RenameDuplicateMaterialName
                     | RLPy.EExportFbxOptions2_RenameTransparencyWithPostFix
                     | RLPy.EExportFbxOptions2_RenameBoneRootToGameType
                     | RLPy.EExportFbxOptions2_RenameBoneToLowerCase
                     | RLPy.EExportFbxOptions2_ResetBoneScale
                     | RLPy.EExportFbxOptions2_ResetSelfillumination
                     | RLPy.EExportFbxOptions2_ExtraWordForUnityAndUnreal
                     | RLPy.EExportFbxOptions2_BakeMouthOpenMotionToMesh
                     | RLPy.EExportFbxOptions2_UnrealIkBone
                     | RLPy.EExportFbxOptions2_UnrealPreset)
            if (prefix or suffix) and hasattr(RLPy, "EExportFbxOptions2_PrefixAndPostfix"):
                flags |= RLPy.EExportFbxOptions2_PrefixAndPostfix
            return flags
        # Custom mode – always include ResetBoneScale (prevents 10x scale issue)
        flags = RLPy.EExportFbxOptions2_ResetBoneScale
        if (prefix or suffix) and hasattr(RLPy, "EExportFbxOptions2_PrefixAndPostfix"):
            flags |= RLPy.EExportFbxOptions2_PrefixAndPostfix
        if self.radio_xup.isChecked():
            flags |= RLPy.EExportFbxOptions2_XUp
        elif self.radio_yup.isChecked():
            flags |= RLPy.EExportFbxOptions2_YUp
        elif self.radio_ue4.isChecked():
            flags |= RLPy.EExportFbxOptions2_UnrealEngine4BoneAxis
        return flags


# ───────── FBX BONE-ROOT MERGE ─────────
# Root motion lives on RL_BoneRoot, which is why iClone cannot drop it on
# export. After export, its keys are baked into its child bone (e.g. Genesis9);
# then the node, its curves and its bind-pose entry are deleted from the FBX.

_FBX_MAGIC = b"Kaydara FBX Binary  \x00"
_FBX_FOOTER_MAGIC = (b"\xf8\x5a\x8c\x6a\xde\xf5\xd9\x7e"
                     b"\xec\xe9\x0c\xe3\x75\x8f\x29\x0b")
_FBX_SCALAR_FMT = {"Y": "<h", "C": "<B", "I": "<i", "F": "<f", "D": "<d", "L": "<q"}
_FBX_ARRAY_FMT = {"f": "f", "d": "d", "l": "q", "i": "i", "b": "b", "c": "b"}
_FBX_AXES = (b"X", b"Y", b"Z")
_FBX_CHANNELS = ((b"Lcl Translation", 0.0), (b"Lcl Rotation", 0.0), (b"Lcl Scaling", 1.0))
_FBX_PIVOT_PROPS = (b"PreRotation", b"PostRotation", b"RotationOffset",
                    b"RotationPivot", b"ScalingOffset", b"ScalingPivot")


class _FbxArray:
    """Array property, kept encoded until it is read or replaced."""
    def __init__(self, kind, raw):
        self.kind, self.raw, self._values = kind, raw, None

    def values(self):
        if self._values is None:
            count, encoding, size = struct.unpack_from("<III", self.raw, 0)
            body = self.raw[12:12 + size]
            if encoding == 1:
                body = zlib.decompress(body)
            self._values = list(struct.unpack(
                "<%d%s" % (count, _FBX_ARRAY_FMT[self.kind]), body))
        return self._values

    def set(self, values):
        self._values, self.raw = list(values), None

    def encode(self):
        if self.raw is None:
            body = zlib.compress(struct.pack(
                "<%d%s" % (len(self._values), _FBX_ARRAY_FMT[self.kind]), *self._values))
            self.raw = struct.pack("<III", len(self._values), 1, len(body)) + body
        return self.raw


class _FbxNode:
    def __init__(self, name, props, children, sentinel):
        self.name, self.props, self.children, self.sentinel = name, props, children, sentinel

    def child(self, name):
        for c in self.children:
            if c.name == name:
                return c
        return None

    def value(self, index=0):
        return self.props[index][1]


def _fbx_read(data):
    if data[:21] != _FBX_MAGIC:
        raise ValueError("not a binary FBX file")
    version = struct.unpack_from("<I", data, 23)[0]
    head_fmt = "<QQQ" if version >= 7500 else "<III"
    null_len = struct.calcsize(head_fmt) + 1

    def read_prop(o):
        kind = chr(data[o]); o += 1
        if kind in _FBX_SCALAR_FMT:
            fmt = _FBX_SCALAR_FMT[kind]
            return [kind, struct.unpack_from(fmt, data, o)[0]], o + struct.calcsize(fmt)
        if kind in "SR":
            size = struct.unpack_from("<I", data, o)[0]
            return [kind, data[o + 4:o + 4 + size]], o + 4 + size
        if kind in _FBX_ARRAY_FMT:
            size = struct.unpack_from("<I", data, o + 8)[0]
            return [kind, _FbxArray(kind, data[o:o + 12 + size])], o + 12 + size
        raise ValueError("unknown FBX property type %r" % kind)

    def read_node(o):
        end, prop_count, _ = struct.unpack_from(head_fmt, data, o)
        name_len = data[o + null_len - 1]
        o += null_len
        if end == 0:
            return None, o
        name = data[o:o + name_len]; o += name_len
        props = []
        for _ in range(prop_count):
            prop, o = read_prop(o)
            props.append(prop)
        children, sentinel = [], False
        while o < end:
            if end - o == null_len and not any(data[o:end]):
                sentinel, o = True, end
                break
            node, o = read_node(o)
            children.append(node)
        return _FbxNode(name, props, children, sentinel), end

    nodes, o = [], 27
    while True:
        node, o = read_node(o)
        if node is None:
            break
        nodes.append(node)
    return version, data[:27], nodes, data[o:o + 16]


def _fbx_write(version, header, nodes, footer_id):
    head_fmt = "<QQQ" if version >= 7500 else "<III"
    null = b"\0" * (struct.calcsize(head_fmt) + 1)
    out = bytearray(header)

    def prop_bytes(kind, value):
        if kind in _FBX_SCALAR_FMT:
            return kind.encode() + struct.pack(_FBX_SCALAR_FMT[kind], value)
        if kind in "SR":
            return kind.encode() + struct.pack("<I", len(value)) + value
        return kind.encode() + value.encode()

    def write_node(node):
        start = len(out)
        props = b"".join(prop_bytes(k, v) for k, v in node.props)
        out.extend(struct.pack(head_fmt, 0, 0, 0))
        out.append(len(node.name))
        out.extend(node.name)
        out.extend(props)
        for c in node.children:
            write_node(c)
        if node.sentinel:
            out.extend(null)
        struct.pack_into(head_fmt, out, start, len(out), len(node.props), len(props))

    for node in nodes:
        write_node(node)
    out.extend(null)
    out.extend(footer_id)
    out.extend(b"\0" * 4)
    # FBX SDK pads (1-16 bytes) so the whole file ends on a 16-byte boundary
    footer_tail = 4 + 120 + len(_FBX_FOOTER_MAGIC)
    out.extend(b"\0" * (-(len(out) + footer_tail) % 16 or 16))
    out.extend(struct.pack("<I", version))
    out.extend(b"\0" * 120)
    out.extend(_FBX_FOOTER_MAGIC)
    return bytes(out)


def _euler_to_matrix(rx, ry, rz):
    """FBX eEulerXYZ angles (degrees) -> 3x3 rotation, R = Rz * Ry * Rx."""
    x, y, z = math.radians(rx), math.radians(ry), math.radians(rz)
    cx, sx, cy, sy = math.cos(x), math.sin(x), math.cos(y), math.sin(y)
    cz, sz = math.cos(z), math.sin(z)
    return ((cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz),
            (cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz),
            (-sy, sx * cy, cx * cy))


def _matrix_to_euler(m, prev=None):
    """3x3 rotation -> eEulerXYZ degrees, unwrapped to stay close to prev."""
    y = math.asin(max(-1.0, min(1.0, -m[2][0])))
    if abs(math.cos(y)) > 1e-6:
        x = math.atan2(m[2][1], m[2][2])
        z = math.atan2(m[1][0], m[0][0])
    else:  # gimbal lock: keep the previous X and solve Z
        x = math.radians(prev[0]) if prev else 0.0
        if y > 0:
            z = x - math.atan2(m[0][1], m[1][1])
        else:
            z = math.atan2(-m[0][1], m[1][1]) - x
    best = None
    for sol in ((x, y, z), (x + math.pi, math.pi - y, z + math.pi)):
        sol = [math.degrees(a) for a in sol]
        if prev is None:
            return sol
        sol = [a + 360.0 * round((p - a) / 360.0) for a, p in zip(sol, prev)]
        cost = sum(abs(a - p) for a, p in zip(sol, prev))
        if best is None or cost < best[0]:
            best = (cost, sol)
    return best[1]


def _fbx_name(node):
    return node.value(1).split(b"\x00\x01")[0]


def _fbx_p70(node):
    props = node.child(b"Properties70")
    return {p.value(0): p for p in props.children} if props else {}


def _fbx_set_p70_vector(node, prop, vec, default):
    p = _fbx_p70(node).get(prop)
    if p is not None:
        for k in range(3):
            p.props[4 + k][1] = vec[k]
    elif any(abs(v - default) > 1e-6 for v in vec):
        node.child(b"Properties70").children.append(_FbxNode(b"P", [
            ["S", prop], ["S", prop], ["S", b""], ["S", b"A"],
            ["D", vec[0]], ["D", vec[1]], ["D", vec[2]]], [], False))


def merge_bone_root(fbx_path, root_name=b"RL_BoneRoot"):
    """Bake root_name into its child bone, delete it and rewrite the FBX."""
    with open(fbx_path, "rb") as f:
        version, header, nodes, footer_id = _fbx_read(f.read())
    top = {n.name: n for n in nodes}
    objects, connections = top[b"Objects"], top[b"Connections"]
    by_id = {n.value(0): n for n in objects.children}
    label = root_name.decode()

    root_id = next((i for i, n in by_id.items()
                    if n.name == b"Model" and _fbx_name(n) == root_name), None)
    if root_id is None:
        return "no %s in the file" % label

    links_to = {}  # parent id -> connections whose parent it is
    for c in connections.children:
        links_to.setdefault(c.value(2), []).append(c)

    def channels(model_id):
        """prop -> (curve-node connection, {axis: AnimationCurve})"""
        out = {}
        for c in links_to.get(model_id, []):
            node = by_id.get(c.value(1))
            if node is not None and node.name == b"AnimationCurveNode" and c.value(0) == b"OP":
                axes = {}
                for c2 in links_to.get(c.value(1), []):
                    curve = by_id.get(c2.value(1))
                    if curve is not None and curve.name == b"AnimationCurve":
                        axes[c2.value(3)[-1:]] = curve
                out[c.value(3)] = (c, axes)
        return out

    # RL_BoneRoot may only own its attribute, its curves and the child bone
    child_links, attr_ids = [], []
    for c in links_to.get(root_id, []):
        node = by_id.get(c.value(1))
        kind = node.name if node is not None else None
        if kind == b"Model" and c.value(0) == b"OO":
            child_links.append(c)
        elif kind == b"NodeAttribute":
            attr_ids.append(c.value(1))
        elif kind != b"AnimationCurveNode":
            raise RuntimeError("%s is linked to an unexpected %s" % (label, kind))
    for c in connections.children:
        if c.value(1) == root_id and c.value(2) != 0:
            raise RuntimeError("%s is not a scene-root bone (or it has skin weights)" % label)
    if len(child_links) != 1:
        raise RuntimeError("%s has %d child bones; expected exactly 1" % (label, len(child_links)))
    child_id = child_links[0].value(1)
    child = by_id[child_id]

    for model_id in (root_id, child_id):
        p70 = _fbx_p70(by_id[model_id])
        order = p70.get(b"RotationOrder")
        if order is not None and order.value(4) != 0:
            raise RuntimeError("%s does not use XYZ rotation order" % _fbx_name(by_id[model_id]).decode())
        for prop in _FBX_PIVOT_PROPS:
            if prop in p70 and any(abs(p70[prop].value(4 + k)) > 1e-6 for k in range(3)):
                raise RuntimeError("%s uses %s, which the merge does not support"
                                   % (_fbx_name(by_id[model_id]).decode(), prop.decode()))

    root_chans, child_chans = channels(root_id), channels(child_id)
    curves = [cv for chans in (root_chans, child_chans)
              for _, axes in chans.values() for cv in axes.values()]
    times = [cv.child(b"KeyTime").value().values() for cv in curves]
    if any(t != times[0] for t in times):
        raise RuntimeError("%s and %s keys are not on the same frames" % (label, _fbx_name(child).decode()))
    count = len(times[0]) if times else 0

    def tracks(model_id, chans):
        """prop -> (static xyz, per-axis key values or None)"""
        p70 = _fbx_p70(by_id[model_id])
        out = {}
        for prop, default in _FBX_CHANNELS:
            static = [p70[prop].value(4 + k) for k in range(3)] if prop in p70 else [default] * 3
            axes = chans.get(prop, (None, {}))[1]
            keys = [axes[a].child(b"KeyValueFloat").value().values() if a in axes else None
                    for a in _FBX_AXES]
            out[prop] = (static, keys)
        return out

    def sample(track, i):
        static, keys = track
        return [static[k] if i is None or keys[k] is None else keys[k][i] for k in range(3)]

    def compose(rt, rr, ct, cr, prev):
        rm, cm = _euler_to_matrix(*rr), _euler_to_matrix(*cr)
        t = [rt[a] + sum(rm[a][b] * ct[b] for b in range(3)) for a in range(3)]
        m = [[sum(rm[a][k] * cm[k][b] for k in range(3)) for b in range(3)] for a in range(3)]
        return t, _matrix_to_euler(m, prev)

    root_tracks, child_tracks = tracks(root_id, root_chans), tracks(child_id, child_chans)
    for i in [None] + list(range(count)):
        if any(abs(v - 1.0) > 1e-4 for v in sample(root_tracks[b"Lcl Scaling"], i)):
            raise RuntimeError("%s is scaled; only unscaled roots can be merged" % label)

    # static (rest) values, then one composed value per key
    static_t, static_r = compose(
        sample(root_tracks[b"Lcl Translation"], None), sample(root_tracks[b"Lcl Rotation"], None),
        sample(child_tracks[b"Lcl Translation"], None), sample(child_tracks[b"Lcl Rotation"], None),
        None)
    _fbx_set_p70_vector(child, b"Lcl Translation", static_t, 0.0)
    _fbx_set_p70_vector(child, b"Lcl Rotation", static_r, 0.0)

    keyed = {b"Lcl Translation": [[], [], []], b"Lcl Rotation": [[], [], []]}
    prev = None
    for i in range(count):
        t, prev = compose(
            sample(root_tracks[b"Lcl Translation"], i), sample(root_tracks[b"Lcl Rotation"], i),
            sample(child_tracks[b"Lcl Translation"], i), sample(child_tracks[b"Lcl Rotation"], i),
            prev)
        for k in range(3):
            keyed[b"Lcl Translation"][k].append(t[k])
            keyed[b"Lcl Rotation"][k].append(prev[k])

    reused = set()
    for prop, values in keyed.items():
        if prop in child_chans:
            conn, axes = child_chans[prop]
        elif prop in root_chans:  # only the root was keyed: hand its curves to the child
            conn, axes = root_chans[prop]
            conn.props[2][1] = child_id
            reused.add(conn.value(1))
        else:
            continue
        for k, axis in enumerate(_FBX_AXES):
            curve = axes.get(axis)
            if curve is None:
                if max(values[k]) - min(values[k]) > 1e-5:
                    raise RuntimeError("%s has no %s %s curve to receive the root motion"
                                       % (_fbx_name(child).decode(), prop.decode(), axis.decode()))
                continue
            curve.child(b"KeyValueFloat").value().set(values[k])
            default = curve.child(b"Default")
            if default is not None:
                default.props[0][1] = values[k][0]
        curve_node_p70 = _fbx_p70(by_id[conn.value(1)])
        for k, axis in enumerate(_FBX_AXES):
            p = curve_node_p70.get(b"d|" + axis)
            if p is not None and count:
                p.props[4][1] = values[k][0]

    # delete the root, its attribute and the curves the child did not take over
    dead = {root_id}
    dead.update(attr_ids)
    for conn, axes in root_chans.values():
        if conn.value(1) not in reused:
            dead.add(conn.value(1))
            dead.update(cv.value(0) for cv in axes.values())
    child_links[0].props[2][1] = 0
    removed_types = {}
    for i in dead:
        removed_types[by_id[i].name] = removed_types.get(by_id[i].name, 0) + 1
    objects.children = [n for n in objects.children if n.value(0) not in dead]
    connections.children = [c for c in connections.children
                            if c.value(1) not in dead and c.value(2) not in dead]

    for pose in objects.children:
        if pose.name != b"Pose":
            continue
        kept = [p for p in pose.children
                if not (p.name == b"PoseNode" and p.child(b"Node").value() == root_id)]
        if len(kept) != len(pose.children):
            pose.child(b"NbPoseNodes").props[0][1] -= len(pose.children) - len(kept)
            pose.children = kept

    definitions = top.get(b"Definitions")
    for d in definitions.children if definitions else []:
        if d.name == b"Count":
            d.props[0][1] -= len(dead)
        elif d.name == b"ObjectType" and d.value(0) in removed_types:
            d.child(b"Count").props[0][1] -= removed_types[d.value(0)]

    tmp_path = fbx_path + ".tmp"
    with open(tmp_path, "wb") as f:
        f.write(_fbx_write(version, header, nodes, footer_id))
    os.replace(tmp_path, fbx_path)
    return "%s merged into %s (%d keys)" % (label, _fbx_name(child).decode(), count)


# ───────── MAIN EXPORT ROUTINE ─────────
def export_clone_fbx():
    """Run the dialog, bake motion, export FBX"""
    # ask where to save
    fbx_path = RLPy.RUi.SaveFileDialog("FBX Files (*.fbx)")
    if not fbx_path:
        RLPy.RMessageBox.Warning("CloneFBX", "Export cancelled – no file selected.")
        return
    if not fbx_path.lower().endswith(".fbx"):
        fbx_path += ".fbx"
    fbx_path = os.path.normpath(fbx_path)

    # checkbox dialog
    dlg = ExportOptionsDialog()
    if dlg.exec_() != QtWidgets.QDialog.Accepted:
        RLPy.RMessageBox.Warning("CloneFBX", "Export cancelled – no options selected.")
        return
    global _last_preset
    _last_preset = dlg.preset()
    opt1 = dlg.options_bitmask()
    opt2 = dlg.get_up_axis_opt2()
    opt3 = RLPy.EExportFbxOptions3__None

    # selected avatar
    avatars = [o for o in RLPy.RScene.GetSelectedObjects()
               if o.GetType() == RLPy.EObjectType_Avatar]
    if not avatars:
        RLPy.RMessageBox.Warning("CloneFBX",
            "No avatar selected.\nPlease highlight ONE avatar and try again.")
        return
    if len(avatars) > 1:
        RLPy.RMessageBox.Warning("CloneFBX",
            "Multiple avatars selected.\nSelect only one avatar for export.")
        return
    avatar = avatars[0]

    # work-area range
    start_tick = RLPy.RGlobal.GetStartTime()
    end_tick   = RLPy.RGlobal.GetEndTime()

    # bake to temp .rlmotion
    fd, motion_path = tempfile.mkstemp(suffix=".rlmotion"); os.close(fd)
    save_opt = RLPy.RSaveFileSetting()
    save_opt.SetSaveType(RLPy.ESaveFileType_Motion)
    save_opt.SetSaveRange(start_tick, end_tick)
    RLPy.RFileIO.SaveFile(avatar, save_opt, motion_path)

    # export FBX
    status = RLPy.RFileIO.ExportFbxFile(
        avatar, fbx_path,
        opt1, opt2, opt3,
        RLPy.EExportTextureSize_Original,
        RLPy.EExportTextureFormat_Default,
        motion_path)

    # cleanup
    try: os.remove(motion_path)
    except OSError: pass

    if status != RLPy.RStatus.Success:
        RLPy.RMessageBox.Error("CloneFBX", f"Export failed – status: {status}")
        return

    if dlg.merges_root():
        try:
            merge_bone_root(fbx_path)
        except Exception as exc:
            RLPy.RMessageBox.Warning("CloneFBX", f"Exported, but RL_BoneRoot was kept:\n{exc}")


# ───────── MENU HOOKUP ─────────
def _add_menu_entry():
    """Create Plugins ▶ CloneTools ▶ CloneFBX and connect it."""
    main_qt = wrapInstance(int(RLPy.RUi.GetMainWindow()), QtWidgets.QMainWindow)

    # top-level "CloneTools" submenu under Plugins
    menu = main_qt.menuBar().findChild(QtWidgets.QMenu, "clone_tools_menu")
    if menu is None:
        menu = wrapInstance(
            int(RLPy.RUi.AddMenu("CloneTools", RLPy.EMenu_Plugins)),
            QtWidgets.QMenu)
        menu.setObjectName("clone_tools_menu")

    # avoid duplicate
    for act in menu.actions():
        if act.text() == "CloneFBX":
            menu.removeAction(act)

    menu.addAction("CloneFBX").triggered.connect(export_clone_fbx)


# iClone calls this when loading a plugin folder
def initialize_plugin():
    _add_menu_entry()


# if you simply "Run" the .py once via Script ▶ Load Python
def run_script():
    _add_menu_entry()
