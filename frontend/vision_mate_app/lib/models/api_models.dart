class ObjectDetection {
  final String name;
  final double confidence;
  final int x;
  final int y;
  final int w;
  final int h;
  final double? distance; // Distance in meters (null if not available)
  final bool isLiDARMeasured; // Whether distance was measured using LiDAR
  final String? position; // Position description (e.g., "center", "left")
  final double? angle; // Angle from center in degrees

  ObjectDetection({
    required this.name,
    required this.confidence,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.distance,
    this.isLiDARMeasured = false,
    this.position,
    this.angle,
  });

  factory ObjectDetection.fromJson(Map<String, dynamic> json) {
    return ObjectDetection(
      name: json['name'] ?? '',
      confidence: (json['confidence'] ?? 0.0).toDouble(),
      x: (json['x'] ?? 0).toInt(),
      y: (json['y'] ?? 0).toInt(),
      w: (json['w'] ?? 0).toInt(),
      h: (json['h'] ?? 0).toInt(),
      distance: json['distance']?.toDouble(),
      isLiDARMeasured: json['is_lidar_measured'] ?? false,
      position: json['position'],
      angle: json['angle']?.toDouble(),
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
      if (distance != null) 'distance': distance,
      'is_lidar_measured': isLiDARMeasured,
      if (position != null) 'position': position,
      if (angle != null) 'angle': angle,
    };
  }

  @override
  String toString() {
    String result = '$name (${(confidence * 100).toStringAsFixed(0)}%)';
    if (distance != null) {
      String source = isLiDARMeasured ? 'LiDAR' : 'estimated';
      result += ' at ${distance!.toStringAsFixed(1)}m ($source)';
    }
    if (position != null) {
      result += ' - $position';
    }
    return result;
  }

  /// Get a detailed description including distance and position
  String getDetailedDescription() {
    List<String> parts = [name];
    
    if (distance != null) {
      String distanceStr = distance! < 1.0 
        ? '${(distance! * 100).toStringAsFixed(0)} centimeters'
        : '${distance!.toStringAsFixed(1)} meters';
      String source = isLiDARMeasured ? 'precisely measured' : 'estimated';
      parts.add('$distanceStr away ($source)');
    }
    
    if (position != null) {
      parts.add('positioned $position');
    }
    
    if (angle != null) {
      String direction = angle! > 0 ? 'right' : 'left';
      parts.add('${angle!.abs().toStringAsFixed(0)} degrees to the $direction');
    }
    
    return parts.join(', ');
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
