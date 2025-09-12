import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import '../config/constants.dart';
import '../models/api_models.dart';

class ApiService {
  static late Dio _dio;
  static String? _workingBaseUrl;

  // Initialize with working URL
  static Future<void> _initializeDio() async {
    if (_workingBaseUrl != null) {
      _dio = Dio(
        BaseOptions(
          baseUrl: _workingBaseUrl!,
          connectTimeout: ApiConfig.requestTimeout,
          receiveTimeout: ApiConfig.requestTimeout,
          sendTimeout: ApiConfig.requestTimeout,
        ),
      );
      return;
    }

    // Try to find a working URL
    for (String url in ApiConfig.fallbackUrls) {
      try {
        print('ApiService: Trying URL: $url');
        Dio testDio = Dio(
          BaseOptions(
            baseUrl: url,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            sendTimeout: const Duration(seconds: 30),
          ),
        );

        Response response = await testDio.get('/health');
        if (response.statusCode == 200) {
          print('ApiService: ✅ Working URL found: $url');
          _workingBaseUrl = url;
          _dio = Dio(
            BaseOptions(
              baseUrl: url,
              connectTimeout: ApiConfig.requestTimeout,
              receiveTimeout: ApiConfig.requestTimeout,
              sendTimeout: ApiConfig.requestTimeout,
            ),
          );
          return;
        }
      } catch (e) {
        print('ApiService: ❌ Failed to connect to $url: $e');
        continue;
      }
    }

    // If no URL works, use the primary one as fallback
    _dio = Dio(
      BaseOptions(
        baseUrl: ApiConfig.baseUrl,
        connectTimeout: ApiConfig.requestTimeout,
        receiveTimeout: ApiConfig.requestTimeout,
        sendTimeout: ApiConfig.requestTimeout,
      ),
    );
  }

  static Future<DetectionResponse> detectObjects(Uint8List imageBytes) async {
    await _initializeDio(); // Ensure we have a working connection

    try {
      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg'),
      });

      Response response = await _dio.post(
        ApiConfig.detectEndpoint,
        data: formData,
      );

      return DetectionResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to detect objects: $e');
    }
  }

  static Future<SceneDescription> describeScene(Uint8List imageBytes) async {
    await _initializeDio(); // Ensure we have a working connection

    try {
      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(imageBytes, filename: 'image.jpg'),
      });

      Response response = await _dio.post(
        ApiConfig.describeEndpoint,
        data: formData,
      );

      return SceneDescription.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to describe scene: $e');
    }
  }

  static Future<AnswerResponse> askQuestion(QuestionRequest request) async {
    await _initializeDio(); // Ensure we have a working connection

    try {
      Response response = await _dio.post(
        ApiConfig.qaEndpoint,
        data: request.toJson(),
      );

      return AnswerResponse.fromJson(response.data);
    } catch (e) {
      throw Exception('Failed to get answer: $e');
    }
  }

  static Future<AnalyzeResponse> analyzeScene(Uint8List imageBytes) async {
    await _initializeDio(); // Ensure we have a working connection

    try {
      print(
        'ApiService: Preparing to send ${imageBytes.length} bytes to analyze endpoint',
      );
      print(
        'ApiService: Using base URL: ${_workingBaseUrl ?? ApiConfig.baseUrl}',
      );

      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          imageBytes,
          filename: 'scene_image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
      });

      print(
        'ApiService: Sending POST request to ${_workingBaseUrl ?? ApiConfig.baseUrl}${ApiConfig.analyzeEndpoint}',
      );

      Response response = await _dio.post(
        ApiConfig.analyzeEndpoint,
        data: formData,
      );

      print(
        'ApiService: Received response with status: ${response.statusCode}',
      );
      print('ApiService: Response data: ${response.data}');

      return AnalyzeResponse.fromJson(response.data);
    } catch (e) {
      print('ApiService: Error analyzing scene: $e');
      if (e is DioException) {
        print('ApiService: Dio error type: ${e.type}');
        print('ApiService: Dio error message: ${e.message}');
        if (e.response != null) {
          print('ApiService: Server response: ${e.response?.data}');
        }
      }
      throw Exception('Failed to analyze scene: $e');
    }
  }

  static Future<Map<String, dynamic>?> findObject(Uint8List imageBytes, String query) async {
    try {
      await _initializeDio();
      print('ApiService: Finding object "$query" with image of ${imageBytes.length} bytes');

      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
        'query': query,
      });

      Response response = await _dio.post(
        '/find-object',
        data: formData,
      );

      print('ApiService: Find object response - Status: ${response.statusCode}');
      print('ApiService: Find object response - Data: ${response.data}');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('ApiService: Error finding object: $e');
      if (e is DioException) {
        print('ApiService: Dio error type: ${e.type}');
        print('ApiService: Dio error message: ${e.message}');
        if (e.response != null) {
          print('ApiService: Server response: ${e.response?.data}');
        }
      }
      return null;
    }
  }

  static Future<Map<String, dynamic>?> navigateTo(Uint8List imageBytes, String destination) async {
    try {
      await _initializeDio();
      print('ApiService: Navigating to "$destination" with image of ${imageBytes.length} bytes');

      FormData formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(
          imageBytes,
          filename: 'image.jpg',
          contentType: MediaType('image', 'jpeg'),
        ),
        'destination': destination,
      });

      Response response = await _dio.post(
        '/navigate-to',
        data: formData,
      );

      print('ApiService: Navigation response - Status: ${response.statusCode}');
      print('ApiService: Navigation response - Data: ${response.data}');

      return response.data as Map<String, dynamic>;
    } catch (e) {
      print('ApiService: Error in navigation: $e');
      if (e is DioException) {
        print('ApiService: Dio error type: ${e.type}');
        print('ApiService: Dio error message: ${e.message}');
        if (e.response != null) {
          print('ApiService: Server response: ${e.response?.data}');
        }
      }
      return null;
    }
  }

  static Future<bool> checkHealth() async {
    // This will try all fallback URLs automatically
    await _initializeDio();

    if (_workingBaseUrl != null) {
      print('✅ Found working backend at: $_workingBaseUrl');
      return true;
    }

    return false;
  }
}
