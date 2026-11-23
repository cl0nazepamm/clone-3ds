# MaxToBodypaint receiver for Cinema 4D R20 (Python 2.7; also runs on Python 3).
#
# 3ds Max's "To BodyPaint" button (MaxToBodypaint.ms) writes send.obj, send.mtl and, last,
# send.json into %LOCALAPPDATA%\MaxToBodypaint. Every half second this checks send.json: a new
# send is merged into the open document and the new objects are selected, ready to paint. Each
# material gets its Max maps, referenced where they are (never copied):
#   base colour -> Luminance only (colour and reflectance off), flat and unlit
#   opacity     -> Alpha (Image Alpha when Max used the bitmap's alpha output)
#
# Install: copy this file into %APPDATA%\MAXON\Cinema 4D R20_<id>\plugins\ and restart
# Cinema 4D. Results print to the Console (Script > Console).
from __future__ import print_function

import io
import json
import os
import re

import c4d

PLUGIN_ID = 1000005  # Maxon's test range (1000001-1000010): fine for a personal plugin
DROP = os.path.join(os.environ.get('LOCALAPPDATA', ''), 'MaxToBodypaint')
JOB = os.path.join(DROP, 'send.json')
PY2 = str is bytes


def native(s):
    """Python 2 Cinema 4D takes UTF-8 byte strings; Python 3 takes str."""
    return s.encode('utf-8') if PY2 and not isinstance(s, bytes) else s


def key(name):
    """Material names compared loosely: the OBJ exporter and importer may change case and
    spaces, and Cinema 4D numbers duplicates ('Skin.1')."""
    if PY2 and isinstance(name, bytes):
        name = name.decode('utf-8', 'replace')
    return re.sub(r'[^a-z0-9]+', '_', re.sub(r'\.\d+$', '', name).lower()).strip('_')


def bitmap(mat, path):
    shader = c4d.BaseShader(c4d.Xbitmap)
    shader[c4d.BITMAPSHADER_FILENAME] = native(path)
    mat.InsertShader(shader)
    return shader


def set_maps(mat, maps):
    """Base colour in Luminance (colour and reflectance off, so it shows flat and unlit);
    opacity in Alpha."""
    if maps.get('color'):
        mat[c4d.MATERIAL_USE_COLOR] = False
        mat[c4d.MATERIAL_USE_REFLECTION] = False
        mat[c4d.MATERIAL_USE_LUMINANCE] = True
        mat[c4d.MATERIAL_LUMINANCE_SHADER] = bitmap(mat, maps['color'])
    if maps.get('opacity'):
        mat[c4d.MATERIAL_USE_ALPHA] = True
        mat[c4d.MATERIAL_ALPHA_SHADER] = bitmap(mat, maps['opacity'])
        mat[c4d.MATERIAL_ALPHA_IMAGEALPHA] = bool(maps.get('opacityAlpha'))
    mat.Message(c4d.MSG_UPDATE)
    mat.Update(True, True)


def top_objects(doc):
    out, o = [], doc.GetFirstObject()
    while o:
        out.append(o)
        o = o.GetNext()
    return out


def import_send(doc, job):
    """Merges the send's OBJ into `doc`; returns (new objects, materials given maps)."""
    objects_before, materials_before = top_objects(doc), doc.GetMaterials()
    flags = c4d.SCENEFILTER_OBJECTS | c4d.SCENEFILTER_MATERIALS
    if not c4d.documents.MergeDocument(doc, native(job['obj']), flags):
        raise RuntimeError('could not import ' + job['obj'])
    # {name: {color, opacity, opacityAlpha}}; an older send has {name: colour path}
    maps = dict((key(k), v if isinstance(v, dict) else {'color': v}) for k, v in job.get('materials', {}).items())
    done = 0
    for mat in doc.GetMaterials():
        if mat in materials_before:
            continue
        m = maps.get(key(mat.GetName()))
        if m:
            set_maps(mat, m)
            done += 1
    new = [o for o in top_objects(doc) if o not in objects_before]
    for i, o in enumerate(new):
        doc.SetActiveObject(o, c4d.SELECTION_NEW if i == 0 else c4d.SELECTION_ADD)
    c4d.EventAdd()
    return new, done


def read_job():
    try:
        with io.open(JOB, encoding='utf-8-sig') as f:
            return json.load(f)
    except (IOError, OSError, ValueError):
        return None  # no send yet, or Max is still writing it


def mark_done(job):
    """send.json is overwritten (never deleted) so the send isn't imported twice."""
    with open(JOB, 'w') as f:
        f.write(json.dumps({'done': job.get('id', '')}))


class Receiver(c4d.plugins.MessageData):
    def GetTimer(self):
        return 500

    def CoreMessage(self, id, bc):
        if id == c4d.MSG_TIMER:
            job = read_job()
            if job and job.get('obj'):
                mark_done(job)  # first: a failing send must not repeat every half second
                try:
                    new, done = import_send(c4d.documents.GetActiveDocument(), job)
                    print('MaxToBodypaint: %d object(s), %d material(s) given their maps' % (len(new), done))
                except Exception as e:
                    print('MaxToBodypaint: ' + str(e))
        return True


if __name__ == '__main__':
    if c4d.plugins.RegisterMessagePlugin(PLUGIN_ID, 'MaxToBodypaint', 0, Receiver()):
        print('MaxToBodypaint: listening for 3ds Max sends in ' + DROP)
