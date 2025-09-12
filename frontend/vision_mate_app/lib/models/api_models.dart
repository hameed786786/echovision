class ObjectDetection {
  final String name;
  final double confidence;
  final int x;
  final int y;
  final int w;
  final int h;

  ObjectDetection({
    required this.name,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  factory ObjectDetection.fromJson(Map<String, dynamic> json) {
    return ObjectDetection(
      name: json['name'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      x: (json['x'] ?? 0).toInt(),
      y: (json['y'] ?? 0).toInt(),
      w: (json['w'] ?? 0).toInt(),
      h: (json['h'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'confidence': confidence,
      'x': x,
      'y': y,
      'w': w,
      'h': h,
    };
  }

  @override
  String toString() {
    return '$name (${(confidence * 100).toStringAsFixed(0)}%)';
  }
}

class DetectionResponse {
  final List<ObjectDetection> objects;

  DetectionResponse({required this.objects});

  factory DetectionResponse.fromJson(Map<String, dynamic> json) {
    var objectsList = json['objects'] as List? ?? [];
    List<ObjectDetection> objects = objectsList
        .map((obj) => ObjectDetection.fromJson(obj))
        .toList();

    return DetectionResponse(objects: objects);
  }
}

class SceneDescription {
  final String description;

  SceneDescription({required this.description});

  factory SceneDescription.fromJson(Map<String, dynamic> json) {
    return SceneDescription(
      description: json['description'] ?? 'No description available',
    );
  }
}

class QuestionRequest {
  final String question;
  final String sceneDescription;
  final List<ObjectDetection> objects;

  QuestionRequest({
    required this.question,
    required this.sceneDescription,
    required this.objects,
  });

  Map<String, dynamic> toJson() {
    return {
      'question': question,
      'scene_description': sceneDescription,
      'objects': objects.map((obj) => obj.toJson()).toList(),
    };
  }
}

class AnswerResponse {
  final String answer;

  AnswerResponse({required this.answer});

  factory AnswerResponse.fromJson(Map<String, dynamic> json) {
    return AnswerResponse(answer: json['answer'] ?? 'No answer available');
  }
}

class AnalyzeResponse {
  final List<ObjectDetection> objects;
  final String sceneDescription;
  final String? extractedText;

  AnalyzeResponse({
    required this.objects, 
    required this.sceneDescription,
    this.extractedText,
  });

  factory AnalyzeResponse.fromJson(Map<String, dynamic> json) {
    var objectsList = json['objects'] as List? ?? [];
    List<ObjectDetection> objects = objectsList
        .map((obj) => ObjectDetection.fromJson(obj))
        .toList();

    return AnalyzeResponse(
      objects: objects,
      sceneDescription: json['scene_description'] ?? 'No description available',
      extractedText: json['extracted_text'],
    );
  }
}
