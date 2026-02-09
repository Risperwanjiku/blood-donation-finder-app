importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.7.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBRlKSDzZDyc0g86wuz_xpqFheXLWhlnoc',
  appId: '1:433036287591:web:74aecbf6eb3ce063097ec2',
  messagingSenderId: '433036287591',
  projectId: 'blood-donation-finder-a2b7c',
  authDomain: 'blood-donation-finder-a2b7c.firebaseapp.com',
  storageBucket: 'blood-donation-finder-a2b7c.firebasestorage.app',
  measurementId: 'G-Q6TG1R2Y9H',
});

const messaging = firebase.messaging();

// Handle background messages
messaging.onBackgroundMessage((payload) => {
  console.log('Received background message:', payload);

  const notificationTitle = payload.notification.title || 'Blood Donation Alert';
  const notificationOptions = {
    body: payload.notification.body || 'Someone needs blood!',
    icon: '/icons/Icon-192.png'
  };

  self.registration.showNotification(notificationTitle, notificationOptions);
});