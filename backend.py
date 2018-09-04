from flask import Flask, render_template, jsonify, request
import random
import json


with open('static/files/small_streetsegs.json') as f:
    streetsegs = json.load(f)


def inBox(lat,lng, bbox):
    # bbox from json has format
    # [south lat, north lat, west long, east long]

    lat = float(lat)
    lng = float(lng)
    bbox = [float(x) for x in bbox]

    if ((bbox[0] <= lat <= bbox[1]) and
        (bbox[2] <= lng <= bbox[3])):
        return True
    else:
        return False



vizapp = Flask(__name__)

@vizapp.route('/')
def hello_world():
    return render_template('viz.html')



@vizapp.route('/ajaxMapClick', methods=['POST'])
def mapclick_test():
    lat = request.form.get('lat')
    lng = request.form.get('lng')
    print(lat)
    print(lng)
    outstring = str(lat) + ", " + str(lng) + " is "
    if inBox(lat,lng,streetsegs['5088685']["boundingBox"]):
        outstring += "inside 5088685 bounding box"
    else:
        outstring += "not inside 5088685 bounding box"
    return jsonify(result = outstring)


@vizapp.route('/ajaxTest', methods=['POST'])
def ajax_test():
    #someint = request.args.get('somenum', -1, type=int)
    someint = request.form.get('somenum')
    print(request.form.get('somenum'))
    return jsonify(result="the data passed was: " + str(someint))


if __name__ == '__main__':
    vizapp.run(host='0.0.0.0',
            port=8888,
            debug = True)


